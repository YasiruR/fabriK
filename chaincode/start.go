package main

import (
	"fmt"
	"github.com/YasiruR/fabriK/chaincode/asset"
	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"github.com/tryfix/log"
	"os"
)

func main() {
	/* invoke chaincode as an external service */
	log.Info(`starting chaincode as an external service`)
	assetCC, err := contractapi.NewChaincode(&asset.SmartContract{})
	if err != nil {
		log.Fatal(fmt.Sprintf(`creating chaincode failed - %v`, err))
	}
	log.Info(`chaincode is created for asset smart contract`)

	ccId := os.Getenv(`CC_ID`)
	ccAddr := os.Getenv(`CC_SERVER_ADDRESS`)
	server := &shim.ChaincodeServer{
		CCID:    ccId,
		Address: ccAddr,
		CC:      assetCC,
		TLSProps: shim.TLSProperties{
			Disabled: true,
		},
	}

	log.Info(fmt.Sprintf("chaincode is up and running at %s with ID: %s", ccAddr, ccId))
	if err = server.Start(); err != nil {
		log.Fatal(fmt.Sprintf("starting server failed - %s", err))
	}
}
