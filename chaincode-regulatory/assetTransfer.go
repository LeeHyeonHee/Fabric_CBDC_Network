/*
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"github.com/hyperledger/fabric-samples/asset-transfer-basic/chaincode-regulatory/chaincode"
)

func main() {
	regulatoryChaincode, err := contractapi.NewChaincode(&chaincode.RegulatoryContract{})
	if err != nil {
		log.Panicf("Error creating asset-transfer-basic chaincode: %v", err)
	}

	if err := regulatoryChaincode.Start(); err != nil {
		log.Panicf("Error starting asset-transfer-basic chaincode: %v", err)
	}
}
