package chaincode

import (
	"encoding/json"
	"fmt"
	"time"
	"strconv"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// "time"
// "strconv"

// SmartContract provides functions for managing an Asset
type RegulatoryContract struct {
	contractapi.Contract
}


type Account struct {
	ID             string `json:"ID"`
	Name		   string `json:"name"`
	Balance 	   int 	  `json:"balance"`	
}

type usageHistory struct {
	ID 			   string `json:"ID"`
	Receiver 	   string `json:"receiver"`
	Price		   string `json:"price"`
	Date		   string `json:"date"`
	Sender 		   string `json:"sender"`
}

func (s *RegulatoryContract) InitAccount(ctx contractapi.TransactionContextInterface) error {

	accounts := []Account{
		{ID: "Bank0", Name: "Shinhan-Main", Balance: 0},
		{ID: "Bank1", Name: "Shinhan-Sub", Balance: 0},
	}

	for _, account := range accounts {
		accountJSON, err := json.Marshal(account)
		if err != nil {
			return err
		}

		err = ctx.GetStub().PutState(account.ID, accountJSON)
		if err != nil {
			return fmt.Errorf("failed to put to world state. %v", err)
		}
	}

	return nil
}

func (s *RegulatoryContract) ReadAccount(ctx contractapi.TransactionContextInterface, id string) (*Account, error) {
	accountJSON, err := ctx.GetStub().GetState(id)

	if err != nil {
		return nil, fmt.Errorf("failed to read world state: %v", err)
	}
	if accountJSON == nil {
		return nil, fmt.Errorf("the asset %s does not exist", id)
	}

	var account Account
	err = json.Unmarshal(accountJSON, &account)

	if err != nil {
		return nil, err
	}

	return &account, nil
}

func (s *RegulatoryContract) UpdateAccount(ctx contractapi.TransactionContextInterface, id string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	if id != "Bank0" {
		return fmt.Errorf("Only the head office of a bank can issue a CBDC from the central bank!!")
	}

	account.Balance = account.Balance + balNum
	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}
	s.TransferHistory(ctx, "Central Bank", id, balance)
	return ctx.GetStub().PutState(id, accountJSON)
}

func (s *RegulatoryContract) UpdateAccountUser(ctx contractapi.TransactionContextInterface, id string, userID string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	account.Balance = account.Balance + balNum
	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}
	// s.TransferHistory(ctx, userID, id, balance)
	return ctx.GetStub().PutState(id, accountJSON)
}

func (s *RegulatoryContract) UpdateSendBalance(ctx contractapi.TransactionContextInterface, id string, rec string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	change := account.Balance - balNum
	
	if change < 0 {
		return fmt.Errorf("Lack of Balance")
	}

	account.Balance = change
	
	// accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}

	params := []string{"UpdateAccount", id, rec, balance}
	queryArgs := make([][]byte, len(params))

	for i, arg := range params {
		queryArgs[i] = []byte(arg)
	}

	response := ctx.GetStub().InvokeChaincode("userchaincode", queryArgs, "user-channel")
	if response.Status != 200 {
		return fmt.Errorf("Failed to query chaincode. Got Error: %s", response.Payload)
	}

	s.TransferHistory(ctx, id, rec, balance)
	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, accountJSON)
}

func (s *RegulatoryContract) UpdateUserBalance(ctx contractapi.TransactionContextInterface, id string, rec string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	change := account.Balance - balNum
	
	if change < 0 {
		return fmt.Errorf("Lack of Balance")
	}

	account.Balance = change
	
	// accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}

	params := []string{"UpdateAccount", id, rec, balance}
	queryArgs := make([][]byte, len(params))

	for i, arg := range params {
		queryArgs[i] = []byte(arg)
	}

	response := ctx.GetStub().InvokeChaincode("userchaincode", queryArgs, "user-channel")
	if response.Status != 200 {
		return fmt.Errorf("Failed to query chaincode. Got Error: %s", response.Payload)
	}

	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, accountJSON)
}

func (s *RegulatoryContract) AccountExist(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	accountJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}

	return accountJSON != nil, nil
}


func (s *RegulatoryContract) ReadTransferHistory(ctx contractapi.TransactionContextInterface) ([]*usageHistory, error) {
	historyJSON, err := ctx.GetStub().GetStateByRange("0", "999")
	if err != nil {
		return nil, err
	}
	defer historyJSON.Close()
	var historys []*usageHistory
	for historyJSON.HasNext() {
		queryResponse, err := historyJSON.Next()
		
		if err != nil {
			return nil, err
		}
		var history usageHistory
		err = json.Unmarshal(queryResponse.Value, &history)
		if err != nil {
			return nil, err 
		}
		historys = append(historys, &history)
	}
	return historys, nil
}

func (s *RegulatoryContract) TransferHistory(ctx contractapi.TransactionContextInterface, rec string, sen string, price string) error {
	history, err := s.ReadTransferHistory(ctx)
	if err != nil {
		return err
	}
	id := strconv.Itoa((len(history)+1))
	now := time.Now()
	customTime := now.Format("2006-01-02 15:04")
	his := usageHistory{
		ID:			id,
		Receiver:   rec,
		Price:		price,
		Date:		customTime,
		Sender:		sen,
	}
	hisJSON, err := json.Marshal(his)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(id, hisJSON)
}

func (s *RegulatoryContract) TransferBalanceBank(ctx contractapi.TransactionContextInterface, id string, rec string, price string) error {
	sender, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	receiver, err := s.ReadAccount(ctx, rec)
	if err != nil {
		return err
	}

	priceNum, e := strconv.Atoi(price)
	if e != nil {
		return e
	}

	sBal := sender.Balance - priceNum
	rBal := receiver.Balance + priceNum
	if sBal < 0 {
		return fmt.Errorf("Lack of balance %s's Account", id)
	}

	sender.Balance = sBal
	receiver.Balance = rBal

	senderJSON, sErr := json.Marshal(sender)
	if sErr != nil {
		return sErr
	}
	receiverJSON, rErr := json.Marshal(receiver)
	if rErr != nil {
		return rErr
	}
	ctx.GetStub().PutState(id, senderJSON)
	ctx.GetStub().PutState(rec, receiverJSON)

	s.TransferHistory(ctx, rec, id, price)
	return nil
}