/*
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"github.com/hyperledger/fabric-samples/asset-transfer-basic/chaincode-go/chaincode"
)

func main() {
	// assetChaincode, err := contractapi.NewChaincode(&testcode.SmartContract{})
	// if err != nil {
	// 	log.Panicf("Error creating asset-transfer-basic chaincode: %v", err)
	// }

	// if err := assetChaincode.Start(); err != nil {
	// 	log.Panicf("Error starting asset-transfer-basic chaincode: %v", err)
	// }

	adminChaincode, errT := contractapi.NewChaincode(&chaincode.AdminContract{})
	if errT != nil {
		log.Panicf("Error creating asset-transfer-basic chaincode: %v", errT)
	}

	if errT := adminChaincode.Start(); errT != nil {
		log.Panicf("Error starting asset-transfer-basic chaincode: %v", errT)
	}
}
