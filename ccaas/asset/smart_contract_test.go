package asset

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-chaincode-go/shimtest"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"github.com/tryfix/log"
	"strconv"
	"testing"
)

const (
	errOK     = "expected: 200, got: %d (msg: %s)"
	errExpect = "expected: %s, got: %s"
)

var (
	testAsset = Asset{Color: "brown", ID: 88, Owner: "Arnold", Value: 989}
)

func newMockStub() *shimtest.MockStub {
	sc := SmartContract{}
	assetCC, err := contractapi.NewChaincode(&sc)
	if err != nil {
		log.Fatal("error creating asset chaincode: ", err)
	}

	stub := shimtest.NewMockStub("mockStub", assetCC)
	if stub == nil {
		log.Fatal("failed to create mock stub")
	}

	return stub
}

func TestSmartContractCreateAsset(t *testing.T) {
	stub := newMockStub()
	testCreate(stub, t)

	in := marshalAsset()
	out := getState(stub, testAsset.ID, t)

	if !bytes.Equal(in, out) {
		t.Fatalf(errExpect, in, out)
	}
}

func TestSmartContractUpdateAsset(t *testing.T) {
	stub := newMockStub()
	testCreate(stub, t)

	testAsset.Color = "blue"
	testAsset.Value = 1500
	testUpdate(stub, t)

	in := marshalAsset()
	out := getState(stub, testAsset.ID, t)

	if !bytes.Equal(in, out) {
		t.Fatalf(errExpect, in, out)
	}
}

func TestSmartContractGetAsset(t *testing.T) {
	stub := newMockStub()
	testCreate(stub, t)

	res := stub.MockInvoke(`1`, [][]byte{[]byte("GetAsset"), []byte(strconv.Itoa(testAsset.ID))})
	if res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}

	in := marshalAsset()
	if !bytes.Equal(in, res.Payload) {
		t.Fatalf(errExpect, in, res.Payload)
	}
}

func TestSmartContractGetAllAssets(t *testing.T) {
	stub := newMockStub()
	testInitLedger(stub, t)

	res := stub.MockInvoke(`2`, [][]byte{[]byte("GetAllAssets")})
	if res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}

	in := marshalAssets()
	if !bytes.Equal(in, res.Payload) {
		t.Fatalf(errExpect, in, res.Payload)
	}
}

func TestSmartContractDeleteAsset(t *testing.T) {
	stub := newMockStub()
	testCreate(stub, t)

	if res := stub.MockInvoke(`6`, [][]byte{
		[]byte("DeleteAsset"), []byte(strconv.Itoa(testAsset.ID)),
	}); res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}

	out := getState(stub, testAsset.ID, t)
	if out != nil {
		t.Fatalf(`state db should be empty after mock delete (%s)`, string(out))
	}
}

func TestSmartContractTransferAsset(t *testing.T) {
	stub := newMockStub()
	testCreate(stub, t)

	if res := stub.MockInvoke(`7`, [][]byte{
		[]byte("TransferAsset"), []byte(strconv.Itoa(testAsset.ID)), []byte("David"),
	}); res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}

	testAsset.Owner = "David"
	out := getState(stub, testAsset.ID, t)
	in := marshalAsset()
	if !bytes.Equal(in, out) {
		t.Fatalf(errExpect, in, out)
	}
}

func testInitLedger(stub *shimtest.MockStub, t *testing.T) {
	if res := stub.MockInvoke(`3`, [][]byte{[]byte("InitLedger")}); res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}
}

func testCreate(stub *shimtest.MockStub, t *testing.T) {
	if res := stub.MockInvoke(`4`, [][]byte{
		[]byte("CreateAsset"), []byte(testAsset.Color), []byte(strconv.Itoa(testAsset.ID)), []byte(testAsset.Owner), []byte(strconv.Itoa(testAsset.Value)),
	}); res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}
}

func testUpdate(stub *shimtest.MockStub, t *testing.T) {
	if res := stub.MockInvoke(`5`, [][]byte{
		[]byte("UpdateAsset"), []byte(testAsset.Color), []byte(strconv.Itoa(testAsset.ID)), []byte(testAsset.Owner), []byte(strconv.Itoa(testAsset.Value)),
	}); res.Status != shim.OK {
		t.Fatalf(errOK, res.Status, res.Message)
	}
}

func getState(stub *shimtest.MockStub, id int, t *testing.T) []byte {
	out, err := stub.GetState(strconv.Itoa(id))
	if err != nil {
		t.Fatalf("failed to retrieve asset info - %s", err.Error())
	}

	return out
}

func marshalAsset() []byte {
	byts, err := json.Marshal(testAsset)
	if err != nil {
		log.Fatal(fmt.Sprintf("failed to marshal asset info - %s", err.Error()))
	}

	return byts
}

func marshalAssets() []byte {
	byts, err := json.Marshal(assets)
	if err != nil {
		log.Fatal(fmt.Sprintf("failed to marshal assets - %s", err.Error()))
	}

	return byts
}
