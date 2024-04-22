package asset

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"strconv"
)

/* This is a sample chaincode implemented as per the Fabric documentation */

type SmartContract struct {
	contractapi.Contract
}

// Asset attributes are defined in alphabetical order to make JSON struct deterministic
type Asset struct {
	Color string `json:"color"`
	ID    int    `json:"id"`
	Owner string `json:"owner"`
	Value int    `json:"value"`
}

func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	assets := []Asset{
		{ID: 1, Color: "blue", Owner: "John Doe", Value: 500},
		{ID: 2, Color: "red", Owner: "Jane Doe", Value: 600},
		{ID: 3, Color: "yellow", Owner: "Bill", Value: 450},
	}

	for _, a := range assets {
		aByts, err := json.Marshal(a)
		if err != nil {
			return fmt.Errorf(`marshal asset failed for asset %d - %w`, a.ID, err)
		}

		if err = ctx.GetStub().PutState(strconv.Itoa(a.ID), aByts); err != nil {
			return fmt.Errorf(`put asset failed for asset %d - %w`, a.ID, err)
		}
	}

	return nil
}

func (s *SmartContract) CreateAsset(ctx contractapi.TransactionContextInterface, color string, id int, owner string, val int) error {
	exists, err := s.AssetExists(ctx, id)
	if err != nil {
		return fmt.Errorf(`create asset failed - %w`, err)
	}

	if exists {
		return fmt.Errorf(`asset with id %d already exists`, id)
	}

	asset := Asset{
		Color: color,
		ID:    id,
		Owner: owner,
		Value: val,
	}

	aByts, err := json.Marshal(asset)
	if err != nil {
		return fmt.Errorf(`marshal asset failed - %w`, err)
	}

	return ctx.GetStub().PutState(strconv.Itoa(asset.ID), aByts)
}

func (s *SmartContract) GetAsset(ctx contractapi.TransactionContextInterface, id int) (*Asset, error) {
	aByts, err := ctx.GetStub().GetState(strconv.Itoa(id))
	if err != nil {
		return nil, fmt.Errorf(`get state failed for asset %d - %w`, id, err)
	}

	if aByts == nil {
		return nil, fmt.Errorf(`asset does not exist for id %d`, id)
	}

	var a Asset
	if err = json.Unmarshal(aByts, &a); err != nil {
		return nil, fmt.Errorf(`unmarshal asset failed for asset %d - %w`, id, err)
	}

	return &a, nil
}

func (s *SmartContract) UpdateAsset(ctx contractapi.TransactionContextInterface, color string, id int, owner string, val int) error {
	exists, err := s.AssetExists(ctx, id)
	if err != nil {
		return fmt.Errorf(`checking asset existence failed - %w`, err)
	}

	if !exists {
		return fmt.Errorf(`asset with id %d does not exist`, id)
	}

	a := Asset{
		Color: color,
		ID:    id,
		Owner: owner,
		Value: val,
	}

	aByts, err := json.Marshal(a)
	if err != nil {
		return fmt.Errorf(`marshal asset failed - %w`, err)
	}

	return ctx.GetStub().PutState(strconv.Itoa(a.ID), aByts)
}

func (s *SmartContract) DeleteAsset(ctx contractapi.TransactionContextInterface, id int) error {
	exists, err := s.AssetExists(ctx, id)
	if err != nil {
		return fmt.Errorf(`checking asset existence failed - %w`, err)
	}

	if !exists {
		return fmt.Errorf(`asset with id %d does not exist`, id)
	}

	return ctx.GetStub().DelState(strconv.Itoa(id))
}

func (s *SmartContract) TransferAsset(ctx contractapi.TransactionContextInterface, id int, newOwner string) error {
	a, err := s.GetAsset(ctx, id)
	if err != nil {
		return fmt.Errorf(`get asset failed - %w`, err)
	}

	a.Owner = newOwner
	aByts, err := json.Marshal(a)
	if err != nil {
		return fmt.Errorf(`marshal asset failed - %w`, err)
	}

	return ctx.GetStub().PutState(strconv.Itoa(id), aByts)
}

func (s *SmartContract) GetAllAssets(ctx contractapi.TransactionContextInterface) ([]*Asset, error) {
	// ranging with empty start and end keys returns all assets in chaincode namespace
	itr, err := ctx.GetStub().GetStateByRange(``, ``)
	if err != nil {
		return nil, fmt.Errorf(`get state by range faied - %w`, err)
	}
	defer itr.Close()

	var ats []*Asset
	for itr.HasNext() {
		res, err := itr.Next()
		if err != nil {
			return nil, fmt.Errorf(`iterating next query result failed - %w`, err)
		}

		var a Asset
		if err = json.Unmarshal(res.Value, &a); err != nil {
			return nil, fmt.Errorf(`unmarshal failed - %w`, err)
		}

		ats = append(ats, &a)
	}

	return ats, nil
}

func (s *SmartContract) AssetExists(ctx contractapi.TransactionContextInterface, id int) (bool, error) {
	aByts, err := ctx.GetStub().GetState(strconv.Itoa(id))
	if err != nil {
		return false, fmt.Errorf(`get state failed for asset %d - %w`, id, err)
	}

	return aByts != nil, nil
}
