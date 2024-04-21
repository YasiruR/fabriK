package main

import (
	"fmt"
	"github.com/YasiruR/fabriK/chaincode/asset"
	"github.com/hyperledger/fabric-chaincode-go/shim"
	"log"
	"os"
)

func main() {
	//assetCC, err := contractapi.NewChaincode(&asset.SmartContract{})
	//if err != nil {
	//	log.Fatalln(fmt.Sprintf(`Error creating chaincode - %v`, err))
	//}
	//
	//if err = assetCC.Start(); err != nil {
	//	log.Fatalln(fmt.Sprintf(`Error starting chaincode - %v`, err))
	//}

	/* TO invoke chaincode as an external service */

	ccId := os.Getenv(`CC_ID`)
	server := &shim.ChaincodeServer{
		CCID:    ccId,
		Address: os.Getenv(`CC_SERVER_ADDRESS`),
		CC:      new(asset.SmartContract),
		TLSProps: shim.TLSProperties{
			Disabled: true,
		},
	}

	if err := server.Start(); err != nil {
		log.Fatalln(fmt.Sprintf("Error starting server: %s\n", err))
	}
}
