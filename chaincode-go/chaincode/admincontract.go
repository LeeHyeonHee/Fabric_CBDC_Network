package chaincode

import (
	"encoding/json"
	"fmt"
	"time"
	"strconv"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"

)

// SmartContract provides functions for managing an Asset
type AdminContract struct {
	contractapi.Contract	
}

type totalBalance struct {
	ID             string `json:"ID"`
	Balance        int    `json:"balance"`
	TBalance       int    `json:"tbalance"`
}

type issueHistory struct {
	ID             string `json:"ID"`
	BankID         string `json:"bankID"`
	Price          string `json:"price"`
	Date           string `json:"date"`
}

const (
	MAX_VAL int = 10000
	CBDC_NAME string = "korea"
)

func (s *AdminContract) InitBalance(ctx contractapi.TransactionContextInterface) error {

	balances := []totalBalance{
		{ID: CBDC_NAME, Balance: 0, TBalance: 0},
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
	newBal := bal.Balance + newBalance

	newTBal := bal.TBalance + newBalance
	if newTBal > MAX_VAL {
		return fmt.Errorf("MAX VAL")
	}

	bal.Balance = newBal
	bal.TBalance = newTBal

// overwriting original asset with new asset

// totalBalanceA := totalBalance{

//  ID:             id,

//  Balance:        newBal,

// }

	totalBalanceJSON, err := json.Marshal(bal)

	if err != nil {
		return err
	}

	s.TransferHistory(ctx, id, strconv.Itoa(newBalance))

	return ctx.GetStub().PutState(id, totalBalanceJSON)

}

func (s *AdminContract) ReadTotalBalanceAll(ctx contractapi.TransactionContextInterface) ([]*totalBalance, error) {

	resultsIterator, err := ctx.GetStub().GetStateByRange("0", "999")

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

func (s *AdminContract) TransferBalance(ctx contractapi.TransactionContextInterface, bankID string, price string) error {

	id := CBDC_NAME
	bal, err := s.ReadTotalBalance(ctx)

	if err != nil {
		return err
	}
	
	priceNum, e := strconv.Atoi(price)
	if e != nil {
		return e
	}
	newBal := bal.Balance - priceNum

	if newBal < 0 {
		return fmt.Errorf("Lack of Balance")
	}

	if bankID != "Bank0" {
		return fmt.Errorf("Only the head office of a bank can issue a CBDC from the central bank!!")
	}

	bal.Balance = newBal
 
	params := []string{"UpdateAccount", bankID, price}
	queryArgs := make([][]byte, len(params))

	for i, arg := range params {
		queryArgs[i] = []byte(arg)
	}

	response := ctx.GetStub().InvokeChaincode("regulatorychaincode", queryArgs, "regulatory-channel")
	if response.Status != 200 {
		return fmt.Errorf("Failed to query chaincode. Got Error: %s", response.Payload)
	}
	error := ctx.GetStub().PutState(bankID, []byte(response.Payload))
	if error != nil {
		return fmt.Errorf("Failed to set asset")
	}
	s.TransferHistory(ctx, bankID, price)
	totalBalanceJSON, err := json.Marshal(bal)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, totalBalanceJSON)
}


// ReadAsset returns the asset stored in the world state with given id.

func (s *AdminContract) ReadTransferHistory(ctx contractapi.TransactionContextInterface) ([]*issueHistory, error) {
	hisoryJSON, err := ctx.GetStub().GetStateByRange("0", "999")
	if err != nil {
		return nil, err
	}
	defer hisoryJSON.Close()
	var historys []*issueHistory
	for hisoryJSON.HasNext() {
		queryResponse, err := hisoryJSON.Next()
		if err != nil {
			return nil, err
		}
		var history issueHistory
		err = json.Unmarshal(queryResponse.Value, &history)
		if err != nil {
			return nil, err
		}
		historys = append(historys, &history)
	}
	return historys, nil
}


func (s *AdminContract) TransferHistory(ctx contractapi.TransactionContextInterface, bankID string, price string) error {
	history, err := s.ReadTransferHistory(ctx)
	if err != nil {
		return err
	}
	id := strconv.Itoa((len(history) + 1))
	now := time.Now()
	customTime := now.Format("2006-01-02 15:04")
	his := issueHistory{
		ID:         id,
		BankID:     bankID,
		Price:      price,
		Date:       customTime,
	}
	hisJSON, err := json.Marshal(his)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, hisJSON)
}


func (s *AdminContract) ReadTransferTest(ctx contractapi.TransactionContextInterface) (string, error) {

	params := []string{"ReadAccount", "0"}
	queryArgs := make([][]byte, len(params))

	for i, arg := range params {
		queryArgs[i] = []byte(arg)
	}

	response := ctx.GetStub().InvokeChaincode("userchaincode", queryArgs, "user-channel")
	if response.Status != 200 {
		return "", fmt.Errorf("Failed to query chaincode. Got Error: %s", response.Payload)
	}
	return string(response.Payload), nil
}