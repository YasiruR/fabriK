package chaincode

import (
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"log"
)

func main() {
	assetCC, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		log.Fatalln(`Error creating chaincode - %w`, err)
	}

	if err = assetCC.Start(); err != nil {
		log.Fatalln(`Error starting chaincode - %w`, err)
	}
}
