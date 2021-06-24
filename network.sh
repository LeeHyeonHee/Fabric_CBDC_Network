DIR="$( cd "$( dirname "$0" )" && pwd )"
CDIR=$DIR/config
BDIR=$DIR/build
ADIR=$BDIR/artifacts
ACDIR=$ADIR/crypto-config
CADIR=$ACDIR/fabric-ca
TDIR=$ADIR/tx
BLKDIR=$ADIR/block
ORDIR=$ACDIR/ordererOrganizations

COMPOSE_FILE_PEER=dockercompose/docker-compose-peer.yaml
COMPOSE_FILE_ORDERER=dockercompose/docker-compose-orderer.yaml
COMPOSE_FILE_COUCH=dockercompose/docker-compose-couch.yaml
COMPOSE_FILE_CLI=dockercompose/docker-compose-cli.yaml
COMPOSE_FILE_CA=dockercompose/docker-compose-ca.yaml
IMAGETAG="2.2"
CA_IMAGETAG="1.4.9"
usermod -aG docker $USER

function up {
    COMPOSE_FILES="-f ${COMPOSE_FILE_PEER}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_ORDERER}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_CLI}"
    IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} up -d 2>&1
    docker ps -a
}

function clean {
    down
    rm -Rf $BDIR
    rm -Rf channel-artifacts
    rm -Rf ./chaincode-go/vendor
    rm -Rf ./chaincode-user/vendor
    rm -Rf ./chaincode-regulatory/vendor
    rm -Rf ./atcc/vendor
}


function generate {
    CRYPTO=${1:-ca}
    mkdir -p $TDIR 2>&1
    mkdir -p $BLKDIR 2>&1

    if [ "$CRYPTO" = "cryptogen" ]; then
        echo "cryptogen ~~~~~~~~~~~~"
        docker run --rm --name fabric-tools \
            -v $CDIR:/tmp \
            -w /tmp \
            hyperledger/fabric-tools:2.2 \
            cryptogen generate --config=/tmp/crypto-config.yaml \
            --output="crypto-config"

        mv $CDIR/crypto-config $ADIR

    fi

    if [ "$CRYPTO" = "ca" ]; then
        echo "Fabric CA ~~~~~~~~~~~~~~"

        IMAGE_TAG=${CA_IMAGETAG} docker-compose -f $COMPOSE_FILE_CA up -d 2>&1
        enrollOrgCA blockchain
        enrollOrgCA security
        enrollOrgCA ai
        enrollOrdererCA
    fi

    echo "systemchannel"
    docker run --rm --name fabric-tools \
        -v $ADIR/crypto-config:/tmp/crypto-config \
        -v $CDIR:/tmp/config \
        -v $BLKDIR:/tmp/block \
        -w /tmp/block \
        hyperledger/fabric-tools:2.2 \
        configtxgen -configPath /tmp/config \
        -profile SystemChannel -channelID system-channel -outputBlock ./genesis.block

    echo "CentralbankChannel"
    docker run --rm --name fabric-tools \
        -v $ADIR/crypto-config:/tmp/crypto-config \
        -v $CDIR:/tmp/config \
        -v $TDIR:/tmp/tx \
        -w /tmp/tx \
        hyperledger/fabric-tools:2.2 \
        configtxgen -configPath /tmp/config \
        -profile CentralbankChannel -channelID centralbank-channel -outputCreateChannelTx ./centralbank-channel.tx

    echo "RegulatoryChannel"
    docker run --rm --name fabric-tools \
        -v $ADIR/crypto-config:/tmp/crypto-config \
        -v $CDIR:/tmp/config \
        -v $TDIR:/tmp/tx \
        -w /tmp/tx \
        hyperledger/fabric-tools:2.2 \
        configtxgen -configPath /tmp/config \
        -profile RegulatoryChannel -channelID regulatory-channel -outputCreateChannelTx ./regulatory-channel.tx

    echo "Userchannel"
    docker run --rm --name fabric-tools \
        -v $ADIR/crypto-config:/tmp/crypto-config \
        -v $CDIR:/tmp/config \
        -v $TDIR:/tmp/tx \
        -w /tmp/tx \
        hyperledger/fabric-tools:2.2 \
        configtxgen -configPath /tmp/config \
        -profile UserChannel -channelID user-channel -outputCreateChannelTx ./user-channel.tx
}

function down {
    COMPOSE_FILES="-f ${COMPOSE_FILE_PEER}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_ORDERER}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_CLI}"
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_CA}"
    IMAGE_TAG=$CA_IMAGETAG docker-compose ${COMPOSE_FILES} down -v 2>&1
    IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} down -v 2>&1
    docker volume ls -qf "dangling=true" | xargs docker volume rm
    docker ps -a
}

function channel_join() {
    number=${1:-0}
    org=${2:-centralbank}
    channelName=${3:-regulatory}
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer${number}.${org}.islab.re.kr/tls
    docker exec -i -t \
        -e CORE_PEER_ID=peer${number}.${org}.islab.re.kr \
        -e CORE_PEER_ADDRESS=peer${number}.${org}.islab.re.kr:7051 \
        -e CORE_PEER_CHAINCODEADDRESS=peer${number}.${org}.islab.re.kr:7052 \
        -e CORE_PEER_GOSSIP_BOOTSTRAP=peer${number}.${org}.islab.re.kr:7051 \
        -e CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer${number}.${org}.islab.re.kr:7051 \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer${number}.${org}.islab.re.kr:7051 \
        cli peer channel join \
            -b /opt/gopath/src/github.com/hyperledger/fabric/peer/block/${channelName}-channel.block
}

function channel_create {
    org=${1:-centralbank}
    channelName=${2:-regulatory}
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    docker exec -i -t \
        -e CORE_PEER_ID=peer0.${org}.islab.re.kr \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        -e CORE_PEER_CHAINCODEADDRESS=peer0.${org}.islab.re.kr:7052 \
        -e CORE_PEER_GOSSIP_BOOTSTRAP=peer0.${org}.islab.re.kr:7051 \
        -e CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.${org}.islab.re.kr:7051 \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer channel create \
            -o orderer0.islab.re.kr:7050 \
            -c ${channelName}-channel \
            -f /opt/gopath/src/github.com/hyperledger/fabric/peer/tx/${channelName}-channel.tx \
            --outputBlock /opt/gopath/src/github.com/hyperledger/fabric/peer/block/${channelName}-channel.block \
            --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
}

function packageChaincode() {
    # sample chaincode

    docker exec -i -t \
        -w /opt/gopath/src/github.com/asset-transfer-basic/chaincode-go \
        cli go mod vendor

    docker exec -i -t \
        cli peer lifecycle chaincode package mychaincode.tar.gz \
            --path /opt/gopath/src/github.com/asset-transfer-basic/chaincode-go \
            --label mychaincode_1.0

    docker exec -i -t \
        -w /opt/gopath/src/github.com/asset-transfer-basic/chaincode-user \
        cli go mod vendor

    docker exec -i -t \
        cli peer lifecycle chaincode package userchaincode.tar.gz \
            --path /opt/gopath/src/github.com/asset-transfer-basic/chaincode-user \
            --label userchaincode_1.0
    
    docker exec -i -t \
        -w /opt/gopath/src/github.com/asset-transfer-basic/chaincode-regulatory \
        cli go mod vendor

    docker exec -i -t \
        cli peer lifecycle chaincode package regulatorychaincode.tar.gz \
            --path /opt/gopath/src/github.com/asset-transfer-basic/chaincode-regulatory \
            --label regulatorychaincode_1.0

    echo "packaging ~~~"
}

function allinstallChaincode() {
    installChaincode 0 centralbank
    installChaincode 0 commercialbank
    installChaincode 1 commercialbank
    installChaincode 0 consumer
    installChaincode 1 consumer
    installChaincode 2 consumer

    installChaincode 0 centralbank mychaincode
    installChaincode 0 centralbank regulatorychaincode
    installChaincode 0 commercialbank regulatorychaincode
    installChaincode 1 commercialbank regulatorychaincode
}

function installChaincode() {
    number=${1:-0}
    org=${2:-centralbank}
    chaincodeName=${3:-userchaincode}
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer${number}.${org}.islab.re.kr/tls
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer${number}.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode install ${chaincodeName}.tar.gz \
            --peerAddresses peer${number}.${org}.islab.re.kr:7051 \
            --tlsRootCertFiles ${TLS_PATH}/server.crt
}

function allqueryInstalled() {
    queryInstalled 0 centralbank
    queryInstalled 0 commercialbank
    queryInstalled 1 commercialbank
    queryInstalled 0 consumer
    queryInstalled 1 consumer
    queryInstalled 2 consumer

}

function queryInstalled() {
    number=${1:-0}
    org=${2:-centralbank}
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer${number}.${org}.islab.re.kr/tls
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer${number}.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode queryinstalled \
            --peerAddresses peer${number}.${org}.islab.re.kr:7051 \
            --tlsRootCertFiles ${TLS_PATH}/server.crt

}

function allapproveForMyOrg() {
    approveForMyOrg centralbank
    sleep 1
    allcheckCommitReadiness
    approveForMyOrg commercialbank
    sleep 1
    allcheckCommitReadiness
    sleep 1
    approveForMyOrg consumer
    allcheckCommitReadiness

    sleep 1

    approveForMyOrg centralbank mychaincode centralbank-channel e8092266ff3b775215fbca08c6fdaa78ba757bb445276c7633446ddd61474f51
    sleep 1
    checkCommitReadiness centralbank mychaincode centralbank-channel
    
    sleep 1
    approveForMyOrg centralbank regulatorychaincode regulatory-channel 170daa7a0c014f7a93a7c521c8024c8833e7a7bf8700758e0eabdfd62d1225e6
    sleep 1
    checkCommitReadiness centralbank regulatorychaincode regulatory-channel
    checkCommitReadiness commercialbank regulatorychaincode regulatory-channel
    
    sleep 1
    approveForMyOrg commercialbank regulatorychaincode regulatory-channel 170daa7a0c014f7a93a7c521c8024c8833e7a7bf8700758e0eabdfd62d1225e6
    sleep 1
    checkCommitReadiness centralbank regulatorychaincode regulatory-channel
    checkCommitReadiness commercialbank regulatorychaincode regulatory-channel
}



function approveForMyOrg() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    packid=${4:-0064fb1abbfc96d67a80bd05353bc4e7cc77d0e7bdd1effa1aa12683c7f22152}
    policy="OR('centralbankOrg.peer'"
    if [ "$channel" == "user-channel" ]; then
        policy+=",'commercialbankOrg.peer','consumerOrg.peer'"
    elif [ "$channel" == "regulatory-channel" ]; then
        policy+=",'commercialbankOrg.peer'"
    fi
    
    policy+=')'

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    # sample chaincode
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode approveformyorg \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            --version 1.0 \
            --package-id ${chaincodeName}_1.0:${packid} \
            --sequence 1 \
            --signature-policy ${policy}

    # my chaincode
    # docker exec -i -t \
    #     -e CORE_PEER_LOCALMSPID=${org}Org \
    #     -e CORE_PEER_TLS_ENABLED=true \
    #     -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
    #     -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
    #     -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
    #     -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
    #     -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
    #     cli peer lifecycle chaincode approveformyorg \
    #         -o orderer0.islab.re.kr:7050 \
    #         --tls --cafile $ORDERER_CA \
    #         --channelID dev-channel \
    #         --name mychaincode \
    #         --version 1.0 \
    #         --package-id mychaincode_1.0:3e94de7b2e34af5406a24b16335a04310d7953f8019268dee9947c655d8f9186 \
    #         --sequence 1 \
    #         --signature-policy "OR('blockchainOrg.member','aiOrg.member','securityOrg.member')"
}

function allcheckCommitReadiness() {
    checkCommitReadiness centralbank
    checkCommitReadiness commercialbank
    checkCommitReadiness consumer
}

function checkCommitReadiness() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    policy="OR('centralbankOrg.peer'"
    if [ "$channel" == "user-channel" ]; then
        policy+=",'commercialbankOrg.peer','consumerOrg.peer'"
    elif [ "$channel" == "regulatory-channel" ]; then
        policy+=",'commercialbankOrg.peer'"
    fi
    
    policy+=')'

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode checkcommitreadiness \
        -o orderer0.islab.re.kr:7050 \
        --channelID ${channel} \
        --tls --cafile $ORDERER_CA \
        --name ${chaincodeName} \
        --version 1.0 \
        --sequence 1 \
        --signature-policy $policy
        # "OR('centralbankOrg.peer','commercialbankOrg.peer','consumerOrg.peer')"
}

function commitChaincodeDefinition() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
  
    policy="OR('centralbankOrg.peer'"
    if [ "$channel" == "user-channel" ]; then
        policy+=",'commercialbankOrg.peer','consumerOrg.peer'"
    elif [ "$channel" == "regulatory-channel" ]; then
        policy+=",'commercialbankOrg.peer'"
    fi

    policy+=')'

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    PEER_0_COMMERCIALBANK_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/commercialbank.islab.re.kr/peers/peer0.commercialbank.islab.re.kr/tls/ca.crt
    PEER_1_COMMERCIALBANK_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/commercialbank.islab.re.kr/peers/peer1.commercialbank.islab.re.kr/tls/ca.crt
    PEER_0_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer0.consumer.islab.re.kr/tls/ca.crt
    PEER_1_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer1.consumer.islab.re.kr/tls/ca.crt
    PEER_2_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer2.consumer.islab.re.kr/tls/ca.crt
    PEER_0_CENTRALBANK_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/centralbank.islab.re.kr/peers/peer0.centralbank.islab.re.kr/tls/ca.crt
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode commit \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            --version 1.0 \
            --peerAddresses peer0.commercialbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_COMMERCIALBANK_TLS_CA_CERT \
            --peerAddresses peer1.commercialbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_1_COMMERCIALBANK_TLS_CA_CERT \
            --peerAddresses peer0.consumer.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_CONSUMER_TLS_CA_CERT \
            --peerAddresses peer1.consumer.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_1_CONSUMER_TLS_CA_CERT \
            --peerAddresses peer2.consumer.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_2_CONSUMER_TLS_CA_CERT \
            --peerAddresses peer0.centralbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_CENTRALBANK_TLS_CA \
            --sequence 1 \
            --signature-policy $policy
}

function commitChaincodeDefinitionTestR() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
  
    policy="OR('centralbankOrg.peer'"
    if [ "$channel" == "user-channel" ]; then
        policy+=",'commercialbankOrg.peer','consumerOrg.peer'"
    elif [ "$channel" == "regulatory-channel" ]; then
        policy+=",'commercialbankOrg.peer'"
    fi

    policy+=')'

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    PEER_0_COMMERCIALBANK_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/commercialbank.islab.re.kr/peers/peer0.commercialbank.islab.re.kr/tls/ca.crt
    PEER_1_COMMERCIALBANK_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/commercialbank.islab.re.kr/peers/peer1.commercialbank.islab.re.kr/tls/ca.crt
    PEER_0_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer0.consumer.islab.re.kr/tls/ca.crt
    PEER_1_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer1.consumer.islab.re.kr/tls/ca.crt
    PEER_2_CONSUMER_TLS_CA_CERT=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/consumer.islab.re.kr/peers/peer2.consumer.islab.re.kr/tls/ca.crt
    PEER_0_CENTRALBANK_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/centralbank.islab.re.kr/peers/peer0.centralbank.islab.re.kr/tls/ca.crt
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode commit \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            --version 1.0 \
            --peerAddresses peer0.commercialbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_COMMERCIALBANK_TLS_CA_CERT \
            --peerAddresses peer1.commercialbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_1_COMMERCIALBANK_TLS_CA_CERT \
            --peerAddresses peer0.centralbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_CENTRALBANK_TLS_CA \
            --sequence 1 \
            --signature-policy $policy
}

function commitChaincodeDefinitionTest() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
  
    policy="OR('centralbankOrg.peer'"
    if [ "$channel" == "user-channel" ]; then
        policy+=",'commercialbankOrg.peer','consumerOrg.peer'"
    elif [ "$channel" == "regulatory-channel" ]; then
        policy+=",'commercialbankOrg.peer'"
    fi

    policy+=')'

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    PEER_0_CENTRALBANK_TLS_CA=$TLS_PATH/ca.crt
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode commit \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            --version 1.0 \
            --peerAddresses peer0.centralbank.islab.re.kr:7051 \
            --tlsRootCertFiles $PEER_0_CENTRALBANK_TLS_CA \
            --sequence 1 \
            --signature-policy $policy
}

function queryCommitted() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer lifecycle chaincode querycommitted \
            --channelID ${channel} \
            --name ${chaincodeName}
}

function chaincodeInvoke() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c '{"Args":["TransferBalance", "Bank1", "1000"]}'
            # -c '{"Args":["UpdateTotalBalance", "5000"]}'
            # -c '{"Args":["InitAccount"]}'
            # -c '{"Args":["InitBalance"]}'
            # -c '{"Args":["TransferTest"]}'
            # -c '{"Args":["TransferBalance", "shinhan", "2000"]}'
            # -c '{"Args":["InitLedger"]}'


}


function chaincode_transfer {
    org=${1:-centralbank}
    chaincodeName=${2:-mychaincode}
    channel=${3:-centralbank-channel}
    bank=$4
    price=$5

    if [ "$channel" == "centralbank-channel" ]; then
        QUERY_TYPE='TransferBalance'
    elif [ "$channel" == "regulatory-channel" ]; then
        QUERY_TYPE='UpdateAccount'
    fi

    if [ "$bank" == "" ] || [ "$price" == "" ]; then
        echo "Please input the bank and price date"
        echo "ex) chaincode invoke centralbank issuanceCentralbank 0 5000"
        exit 0
    fi

    query={'"'Args'"':['"'$QUERY_TYPE'"','"'Bank$bank'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}

function chaincode_transfer_user {
    org=${1:-consumer}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    bank=$4
    user=$5
    price=$6

    if [ "$channel" == "user-channel" ]; then
        QUERY_TYPE='UpdateAccount'
    elif [ "$channel" == "regulatory-channel" ]; then
        QUERY_TYPE='UpdateSendBalance'
    fi

    if [ "$bank" == "" ] || [ "$user" == "" ] || [ "$price" == "" ]; then
        echo "Please input the bank, user and price data"
        echo "ex) chaincode invoke regulatory issuanceRegulatory 0 0 5000"
        exit 0
    fi

    query={'"'Args'"':['"'$QUERY_TYPE'"','"'Bank$bank'"','"'User$user'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}

function chaincode_transfer_user_to_user {
    org=${1:-consumer}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    bank=$4
    user=$5
    price=$6

    if [ "$channel" == "user-channel" ]; then
        QUERY_TYPE='UpdateUserAccount'
    elif [ "$channel" == "regulatory-channel" ]; then
        QUERY_TYPE='UpdateUserBalance'
    fi

    query={'"'Args'"':['"'$QUERY_TYPE'"','"'Bank$bank'"','"'User$user'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}

function chaincode_transfer_cbdc_user_fn {
    org=${1:-consumer}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    sender=$4
    receiver=$5
    price=$6
    arg=$7

    QUERY_TYPE=''
    if [ "$channel" == "user-channel" ]; then
        QUERY_TYPE='TransferBalanceUser'
    elif [ "$channel" == "regulatory-channel" ]; then
        QUERY_TYPE='UpdateAccountUser'
    fi

    if [ "$sender" == "" ] || [ "$receiver" == "" ] || [ "$price" == "" ]; then
        echo "Please input the send user, receiver user and price data"
        echo "ex) chaincode invoke consumer issuanceUser 0 1 500"
        exit 0
    fi

    query={'"'Args'"':['"'$QUERY_TYPE'"'
    
    if [ "$QUERY_TYPE" == "TransferBalanceUser" ]; then
        query+=,'"'$sender'"','"'User$receiver'"','"'User$price'"','"'$arg'"']}
    elif [ "$QUERY_TYPE" == "UpdateAccountUser" ]; then
        query+=,'"'$sender'"','"'User$receiver'"','"'$arg'"']}
    fi 
    
    
    
    # ,'"'User$sender'"','"'User$receiver'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}


function chaincode_invoke_central {
    org=${1:-centralbank}
    chaincodeName=${2:-mychaincode}
    channel=${3:-centralbank-channel}
    QUERY_TYPE=UpdateTotalBalance
    price=$5

    if [ "$price" == "" ]; then
        echo "Please input the price data"
        echo "ex) chaincode invoke centralbank newIssuance 5000"
        exit 0
    fi


    query={'"'Args'"':['"'$QUERY_TYPE'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}

function chaincode_invoke_regulatory {
    org=${1:-commercialbank}
    chaincodeName=${2:-regulatorychaincode}
    channel=${3:-regulatory-channel}
    QUERY_TYPE=$4
    sender=$5
    receiver=$6
    price=$7

    if [ "$price" == "" ] || [ "$sender" == "" ] || [ "$receiver" == "" ]; then
        echo "Please input the send bank, receiver bank and price data"
        echo "ex) chaincode invoke regulatory transferToBank 0 1 2000"
        exit 0
    fi

    query={'"'Args'"':['"'TransferBalanceBank'"','"'Bank$sender'"','"'Bank$receiver'"','"'$price'"']}
    
    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}


function chaincodeInvokeInit {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    QUERY_TYPE=''
    if [ "$channel" == "user-channel" ]; then
        QUERY_TYPE='InitLedger'
    elif [ "$channel" == "regulatory-channel" ]; then
        QUERY_TYPE='InitAccount'
    else 
        QUERY_TYPE='InitBalance'
    fi 
    query={'"'Args'"':['"'$QUERY_TYPE'"']}

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode invoke \
            -o orderer0.islab.re.kr:7050 \
            --tls --cafile $ORDERER_CA \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query
}

function chaincodeQuery() {
    org=${1:-centralbank}
    chaincodeName=${2:-userchaincode}
    channel=${3:-user-channel}
    QUERY_TYPE=$4
    user=$5
    query={'"'Args'"':['"'$QUERY_TYPE'"'
    if [ "$user" != '' ]; then
        query+=,'"'$user'"'
    fi
    query+=]}

    TLS_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/peers/peer0.${org}.islab.re.kr/tls
    ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/islab.re.kr/orderers/orderer0.islab.re.kr/msp/tlscacerts/tlsca.islab.re.kr-cert.pem
    docker exec -i -t \
        -e CORE_PEER_LOCALMSPID=${org}Org \
        -e CORE_PEER_TLS_ENABLED=true \
        -e CORE_PEER_TLS_CERT_FILE=$TLS_PATH/server.crt \
        -e CORE_PEER_TLS_KEY_FILE=$TLS_PATH/server.key \
        -e CORE_PEER_TLS_ROOTCERT_FILE=$TLS_PATH/ca.crt \
        -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${org}.islab.re.kr/users/Admin@${org}.islab.re.kr/msp \
        -e CORE_PEER_ADDRESS=peer0.${org}.islab.re.kr:7051 \
        cli peer chaincode query \
            --channelID ${channel} \
            --name ${chaincodeName} \
            -c $query

            
}

function usage {
    echo 'up | down | generate | channel | deployCC'
}

function channel_usage {
    echo 'create | join'
}

function chaincode_usage {
    echo 'install | invoke | query'
}

function all {
    generate cryptogen
    up
    channel create centralbank centralbank
    channel create centralbank regulatory
    channel create centralbank user
    sleep 10s
    channel join 0 centralbank centralbank
    channel join 0 centralbank regulatory
    channel join 0 commercialbank regulatory
    channel join 1 commercialbank regulatory
    channel join 0 centralbank user
    channel join 0 commercialbank user
    channel join 1 commercialbank user
    channel join 0 consumer user
    channel join 1 consumer user
    channel join 2 consumer user
    # chaincode install
    # chaincode invoke
    # sleep 5s
    # chaincode query
}

function chaincode_install {
    packageChaincode
    allinstallChaincode
    allqueryInstalled
    # allapproveForMyOrg
    # commitChaincodeDefinition centralbank
    # commitChaincodeDefinitionTest centralbank mychaincode centralbank-channel
    # commitChaincodeDefinitionTestR centralbank regulatorychaincode regulatory-channel
    # queryCommitted centralbank
    # queryCommitted consumer
    # queryCommitted centralbank mychaincode centralbank-channel
    # queryCommitted centralbank regulatorychaincode regulatory-channel
    # queryCommitted commercialbank regulatorychaincode regulatory-channel

    # chaincodeInvokeInit centralbank mychaincode centralbank-channel
    # chaincodeInvokeInit commercialbank regulatorychaincode regulatory-channel
    # chaincodeInvokeInit centralbank userchaincode user-channel
    
}


function chaincode_invoke {
    object=$1
    shift
    method=$1
    shift
    if [ "$object" == 'centralbank' ]; then
        if [ "$method" == 'issuanceCentralbank' ]; then
            chaincode_transfer_admin $@
        elif [ "$method" == 'newIssuance' ]; then 
            chaincode_invoke_central centralbank mychaincode centralbank-channel $method $1
        else
            invoke_help $object
        fi
    elif [ "$object" == 'regulatory' ]; then
        if [ "$method" == 'issuanceRegulatory' ]; then
            chaincode_transfer_regulatory $@
        elif [ "$method" == 'transferToBank' ]; then
            chaincode_invoke_regulatory commercialbank regulatorychaincode regulatory-channel $method $1 $2 $3
        else
            invoke_help $object
        fi
    elif [ "$object" == 'consumer' ]; then
        if [ "$method" == 'issuanceUser' ]; then
            chaincode_transfer_cbdc_user $1 $2 $3
        else
            invoke_help $object
        fi
    else
        invoke_help
    fi
}

function chaincode_query {
    object=$1
    shift
    method=$1
    shift

    # if [ "$method" == 'viewRecordUser' ]; then
    #         chaincodeQuery centralbank userchaincode user-channel ReadTransferHistory
    #     el

    if [ "$object" == 'centralbank' ]; then
        if [ "$method" == 'viewRecordRegulatory' ]; then 
            chaincodeQuery centralbank regulatorychaincode regulatory-channel ReadTransferHistory
        elif [ "$method" == 'viewRecordCentral' ]; then 
            chaincodeQuery centralbank mychaincode centralbank-channel ReadTransferHistory
        elif [ "$method" == 'viewCentralBankAccount' ]; then 
            chaincodeQuery centralbank mychaincode centralbank-channel ReadTotalBalance
        else
            query_help $object
        fi
    elif [ "$object" == 'regulatory' ]; then
        if [ "$method" == 'viewBankAccount' ]; then
            chaincodeQuery commercialbank regulatorychaincode regulatory-channel ReadAccount Bank$1
        elif [ "$method" == 'viewRecordAccount' ]; then
            chaincodeQuery commercialbank regulatorychaincode regulatory-channel ReadTransferHistory
        elif [ "$method" == 'viewRecordUser' ]; then
            chaincodeQuery commercialbank userchaincode user-channel ReadTransferHistory
        else
            query_help $object
        fi
    elif [ "$object" == 'consumer' ]; then
        if [ "$method" == 'viewUserAccount' ]; then
            chaincodeQuery commercialbank userchaincode user-channel ReadAccount User$1
        elif [ "$method" == 'viewRecordAccount' ]; then
            chaincodeQuery commercialbank userchaincode user-channel ReadHistoryUserOnly User$1
        else
            query_help $object
        fi
    else
        query_help
    fi
}

function invoke_help {

    mode=$1

    echo " "
    if [ "$mode" == "centralbank" ]; then
        echo "centralbank is Two invoke functions are possible"
        echo "issuanceCentralbank, newIssuance"
        echo " "
        echo "issuanceCentralbank is transfer the issued CBDC to the regulatory bank"
        echo "It is requires the bank code and the amount parameter."
        echo "ex) chaincode invoke centralbank issuanceCentralbank 0 4000"
        echo " "
        echo "newIssuance is It is a function to issue a new CBDC."
        echo "It is requires the amount parameter."
        echo "ex) chaincode invoke centralbank newIssuance 3000"
    elif [ "$mode" == "regulatory" ]; then
        echo "regulatory is Two invoke functions are possible"
        echo "issuanceRegulatory, transferToBank"
        echo " "
        echo "issuanceRegulatory is transfer the issued CBDC to the user"
        echo "It is requires the bank code receive user code and the amount parameter."
        echo "ex) chaincode invoke regulatory issuanceRegulatory 0 1 1000"
        echo " "
        echo "transferToBank is transfer to other bank function."
        echo "It is requires the bank code, receive bank code and amount parameter."
        echo "ex) chaincode invoke regulatory transferToBank 0 1 2000"
    elif [ "$mode" == "consumer" ]; then
        echo "consumer is one invoke functions are possible"
        echo "issuanceUser"
        echo " "
        echo "issuanceUser is transfer CBDC the other user"
        echo "It is requires the user code, receiver user code and the amount parameter."
        echo "ex) chaincode invoke centralbank issuanceUser 0 1 300"
        echo " "
    else 
        echo 'Please enter the valid user'
        echo 'Type are centralbank, regulatory, consumer'
    fi

}

function query_help {

    mode=$1

    echo " "
    if [ "$mode" == "centralbank" ]; then
        echo "centralbank is Three query functions are possible"
        echo "viewRecordRegulatory, viewRecordCentral, viewCentralBankAccount"
        echo " "
        echo "viewRecordRegulatory is a function to inquire about a bank's CBDC transaction record."
        echo "ex) chaincode query centralbank viewRecordRegulatory"
        echo " "
        echo "viewRecordCentral is a function to inquire about a central bank's CBDC transaction record."
        echo "ex) chaincode query centralbank viewRecordCentral"        
        echo " "
        echo "viewCentralBankAccount is a method that shows the central bank's CBDC balance."
        echo "ex) chaincode query centralbank viewCentralBankAccount"
    elif [ "$mode" == "regulatory" ]; then
        echo "ragulatory is Three query functions are possible"
        echo "viewBankAccount, viewRecordAccount, viewRecordUser"
        echo " "
        echo "viewBankAccount is a function to check the current balance of commercial banks."
        echo "It is Requires the bank code parameter."
        echo "ex) chaincode query regulatory viewBankAccount 0"
        echo " "
        echo "viewRecordAccount is function checks the CBDC transaction record of a commercial bank."
        echo "ex) chaincode query regulatory viewRecordAccount"
        echo " "
        echo "viewRecordUser is a function to inquire about a user's CBDC transaction record."
        echo "ex) chaincode query regulatory viewRecordUser"
    elif [ "$mode" == "consumer" ]; then
        echo "consumer is two query functions are possible"
        echo "viewUserAccount, viewRecordAccount"
        echo " "
        echo "viewUserAccount is a function to check the current balance of user."
        echo "It is Requires the user code parameter."
        echo "ex) chaincode query consumer viewUserAccount 0"
        echo " "
        echo "viewRecordAccount is a function that can check the user's transaction record."
        echo "It is Requires the user code parameter."
        echo "ex) chaincode query consumer viewRecordAccount 0"
    else 
        echo 'Please enter the valid user'
        echo 'Type are centralbank, regulatory, consumer'
    fi

}

function chaincode_transfer_admin {
    chaincode_transfer centralbank mychaincode centralbank-channel $1 $2
    if [ $? == 0 ]; then 
        chaincode_transfer commercialbank regulatorychaincode regulatory-channel $1 $2
    fi
}

function chaincode_transfer_regulatory {
    chaincode_transfer_user commercialbank regulatorychaincode regulatory-channel $1 $2 $3
    if [ $? == 0 ]; then    
        chaincode_transfer_user commercialbank userchaincode user-channel $1 $2 $3
    fi
}

function chaincode_transfer_cbdc_user {
    chaincode_transfer_cbdc_user_fn commercialbank userchaincode user-channel Bank1 $1 $2 $3
    if [ $? == 0 ]; then
        chaincode_transfer_cbdc_user_fn commercialbank regulatorychaincode regulatory-channel Bank1 $1 $2 $3
        if [ $? == 0 ]; then
            sleep 2
            chaincode_transfer_user_to_user commercialbank regulatorychaincode regulatory-channel 1 $2 $3
            if [ $? == 0 ]; then
                chaincode_transfer_user_to_user commercialbank userchaincode user-channel 1 $2 $3
            fi
        fi
    fi
} 

function chaincode {
    case $1 in
        install | invoke | query)
            cmd=$1
            shift
            chaincode_$cmd $@
            ;;
        *)
            chaincode_usage
			exit
            ;;
    esac
}

function channel {
    case $1 in
        create | join )
            cmd=$1
            shift
            channel_$cmd $@
            ;;
        *)
            channel_usage
			exit
            ;;
    esac
}

function main {
    case $1 in
        all | up | clean | down | generate | channel | chaincodeinstall | chaincode )
            cmd=$1
            shift
            $cmd $@
            ;;
        *)

            usage
			exit
            ;;
    esac
}

main $@