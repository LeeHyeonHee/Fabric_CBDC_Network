package chaincode

import (
	"encoding/json"
	"fmt"
	"time"
	"strconv"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)



// SmartContract provides functions for managing an Asset
type UserContract struct {
	contractapi.Contract
}

const (
	MAX_VAL int = 1000
)

// Asset describes basic details of what makes up a simple asset
type UserAccount struct {
	ID             string `json:"ID"`
	Name 		   string `json:"name"`
	Balance		   int 	  `json:"balance"`
}

type AccountHistory struct {
	ID				string `json:"ID"`
	Receiver		string `json:"receiver"`
	Price			string `json:"price"`
	Date			string `json:"date"`
	Sender 			string `json:"sender"`
}


// InitLedger adds a base set of assets to the ledger
func (s *UserContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	// 개인 피어 수 만큼 초기 세팅
	accounts := []UserAccount{
		{ID: "User0", Name: "Hyeon Hee", Balance: 0},
		{ID: "User1", Name: "Geum Bo", Balance: 0},
		{ID: "User2", Name: "Test", Balance: 0},
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

func (s *UserContract) ReadAccount(ctx contractapi.TransactionContextInterface, id string) (*UserAccount, error) {
	accountJSON, err := ctx.GetStub().GetState(id)

	if err != nil {
		return nil, fmt.Errorf("failed to read world state: %v", err)
	}
	if accountJSON == nil {
		return nil, fmt.Errorf("the account %s does not exist", id)
	}

	var account UserAccount
	err = json.Unmarshal(accountJSON, &account)

	if err != nil {
		return nil, err
	}

	return &account, nil
}

// 은행에서 돈발행 
func (s *UserContract) UpdateAccount(ctx contractapi.TransactionContextInterface, bankID string, id string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	newBal := account.Balance + balNum
	if newBal > MAX_VAL {
		return fmt.Errorf("Individuals cannot own more than %s in CBDC.", MAX_VAL)
	}
	account.Balance = newBal
	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}

	// 기록 
	s.TransferHistory(ctx, id, bankID, balance)
	return ctx.GetStub().PutState(id, accountJSON)	
}

// 은행에서 돈발행 
func (s *UserContract) UpdateUserAccount(ctx contractapi.TransactionContextInterface, bankID string, id string, balance string) error {
	account, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	balNum, e := strconv.Atoi(balance)
	if e != nil {
		return e
	}

	newBal := account.Balance + balNum
	if newBal > MAX_VAL {
		return fmt.Errorf("Individuals cannot own more than %s in CBDC.", MAX_VAL)
	}
	account.Balance = newBal
	accountJSON, err := json.Marshal(account)
	if err != nil {
		return err
	}
	
	return ctx.GetStub().PutState(id, accountJSON)	
}

// user 끼리의 돈전송 
func (s *UserContract) TransferBalanceUser(ctx contractapi.TransactionContextInterface, bankID string, id string, rec string, price int) error {
	sender, err := s.ReadAccount(ctx, id)
	if err != nil {
		return err
	}
	receiver, err := s.ReadAccount(ctx, rec)
	if err != nil {
		return err
	}

	sBal := sender.Balance - price
	rBal := receiver.Balance + price
	if sBal < 0 {
		return fmt.Errorf("Lack of balance %s's Account", id)
	}
	if rBal > MAX_VAL {
		return fmt.Errorf("Individuals cannot own more than %s in CBDC.", MAX_VAL)
	}
	sender.Balance = sBal
	// receiver.Balance = rBal

	senderJSON, sErr := json.Marshal(sender)
	if sErr != nil {
		return sErr
	}
	// receiverJSON, rErr := json.Marshal(receiver)
	// if rErr != nil {
	// 	return rErr
	// }
	params := []string{"AccountExist", bankID}
	queryArgs := make([][]byte, len(params))

	for i, arg := range params {
		queryArgs[i] = []byte(arg)
	}
	response := ctx.GetStub().InvokeChaincode("regulatorychaincode", queryArgs, "regulatory-channel")
	if response.Status != 200 {
		return fmt.Errorf("Failed to query chaincode. Got Error: %s", response.Payload)
	}

	// ctx.GetStub().PutState(rec, receiverJSON)

	//기록 
	s.TransferHistory(ctx, id, rec, strconv.Itoa(price))
	return ctx.GetStub().PutState(id, senderJSON)
}

func (s *UserContract) TransferHistory(ctx contractapi.TransactionContextInterface, rec string, sen string, price string) error {
	history, err := s.ReadTransferHistory(ctx)
	if err != nil {
		return err
	}
	id := strconv.Itoa((len(history)+1))
	now := time.Now()
	customTime := now.Format("2006-01-02 15:04")
	his := AccountHistory{
		ID:			id,
		Receiver: 	rec,
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

func (s *UserContract) ReadTransferHistory(ctx contractapi.TransactionContextInterface) ([]*AccountHistory, error) {
	historyJSON, err := ctx.GetStub().GetStateByRange("0", "999")
	if err != nil {
		return nil, err
	}
	defer historyJSON.Close()
	var historys []*AccountHistory
	for historyJSON.HasNext() {
		queryResponse, err := historyJSON.Next()

		if err != nil {
			return nil, err
		}
		var history AccountHistory
		err = json.Unmarshal(queryResponse.Value, &history)
		if err != nil {
			return nil, err
		}
		historys = append(historys, &history)
	}
	return historys, nil
}


func (s *UserContract) ReadHistoryUserOnly(ctx contractapi.TransactionContextInterface, userID string) ([]*AccountHistory, error) {
	historyJSON, err := ctx.GetStub().GetStateByRange("0", "999")
	if err != nil {
		return nil, err
	}
	defer historyJSON.Close()
	var historys []*AccountHistory
	for historyJSON.HasNext() {
		queryResponse, err := historyJSON.Next()

		if err != nil {
			return nil, err
		}
		var history AccountHistory
		err = json.Unmarshal(queryResponse.Value, &history)
		if err != nil {
			return nil, err
		}
		if history.Receiver == userID || history.Sender == userID{
			historys = append(historys, &history)
		}
	}
	return historys, nil
}