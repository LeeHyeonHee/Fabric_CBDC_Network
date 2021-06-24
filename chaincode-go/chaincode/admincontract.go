package chaincode

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)


// SmartContract provides functions for managing an Asset
type AdminContract struct {
	contractapi.Contract
}


type totalBalance struct {
	ID             string `json:"ID"`
	Balance 	   int 	  `json:"balance"`
	
}

const ( 
	MAX_VAL int = 10000
	CBDC_NAME string = "korea"
)

func (s *AdminContract) InitBalance(ctx contractapi.TransactionContextInterface) error {

	balances := []totalBalance{
		{ID: CBDC_NAME, Balance: 1000},
	}

	for _, balance := range balances {
		balanceJSON, err := json.Marshal(balance)
		if err != nil {
			return err
		}

		err = ctx.GetStub().PutState(balance.ID, balanceJSON)
		if err != nil {
			return fmt.Errorf("failed to put to world state. %v", err)
		}
	}

	return nil
}

// ReadAsset returns the asset stored in the world state with given id.
func (s *AdminContract) ReadTotalBalance(ctx contractapi.TransactionContextInterface) (*totalBalance, error) {
	id := CBDC_NAME
	totalBalanceJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if totalBalanceJSON == nil {
		return nil, fmt.Errorf("the asset %s does not exist", id)
	}

	var totalBalance totalBalance
	err = json.Unmarshal(totalBalanceJSON, &totalBalance)
	if err != nil {
		return nil, err
	}

	return &totalBalance, nil
}

// UpdateAsset updates an existing asset in the world state with provided parameters.
func (s *AdminContract) UpdateTotalBalance(ctx contractapi.TransactionContextInterface, newBalance int) error {
	id := CBDC_NAME
	bal, err := s.ReadTotalBalance(ctx)
	if err != nil {
		return err
	}
	// totalBalanceJSON, err := ctx.GetStub().GetState(id)
	// if err != nil {
	// 	return err
	// }
	// if totalBalanceJSON == nil {
	// 	return fmt.Errorf("the asset %s does not exist")
	// }
	
	// var change totalBalance 
	// error := json.Unmarshal(totalBalanceJSON, &change)
	// if error != nil {
	// 	return error
	// }
    
	// if change.Balance + balance > MAX_VAL {
	// 	return fmt.Errorf("MAX VAL")
	// }
    newBal := bal.Balance + newBalance

	if newBal > MAX_VAL {
		return fmt.Errorf("MAX VAL")
	}
	bal.Balance = newBal

	// overwriting original asset with new asset
	// totalBalanceA := totalBalance{
	// 	ID:             id,
	// 	Balance:        newBal,
	// }
    fmt.Println(bal.Balance)
	totalBalanceJSON, err := json.Marshal(bal)
    fmt.Println(bal.Balance)
	if err != nil {
		return err
	}
    fmt.Println(bal.Balance)
	return ctx.GetStub().PutState(id, totalBalanceJSON)
}

func (s *AdminContract) ReadTotalBalanceAll(ctx contractapi.TransactionContextInterface) ([]*totalBalance, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var balances []*totalBalance
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var balance totalBalance
		err = json.Unmarshal(queryResponse.Value, &balance)
		if err != nil {
			return nil, err
		}
		balances = append(balances, &balance)
	}

	return balances, nil
}