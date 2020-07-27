package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"time"

	"broker-webapp/quotes"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

const (
	port       = 8080
	quotesURL  = "https://stock-quotes-service:8090/quotes"
	socketPath = "unix:///tmp/agent.sock"
)

var (
	latestQuotes = []*quotes.Quote(nil)
	latestUpdate = time.Now()
	// Stock quotes provider SPIFFE ID
	quotesProviderSpiffeID = spiffeid.Must("stocksmarket.org", "quotes-service")
	x509Src                *workloadapi.X509Source
	bundleSrc              *workloadapi.BundleSource
)

func main() {
	log.Print("Webapp waiting for an X.509 SVID...")

	ctx := context.Background()

	var err error
	x509Src, err = workloadapi.NewX509Source(ctx,
		workloadapi.WithClientOptions(
			workloadapi.WithAddr(socketPath),
			//workloadapi.WithLogger(logger.Std),
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Webapp waiting for a trust bundle...")

	bundleSrc, err = workloadapi.NewBundleSource(ctx,
		workloadapi.WithClientOptions(
			workloadapi.WithAddr(socketPath),
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Addr: fmt.Sprintf(":%d", port),
	}
	http.HandleFunc("/quotes", quotesHandler)

	log.Printf("Webapp listening on port %d...", port)

	err = server.ListenAndServe()
	if err != nil {
		log.Fatal(err)
	}
}

func quotesHandler(resp http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodGet {
		resp.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	data, err := getQuotesData()

	if data != nil {
		latestQuotes = data
		latestUpdate = time.Now()
	} else {
		data = latestQuotes
	}

	quotes.Page.Execute(resp, map[string]interface{}{
		"Data":        data,
		"Err":         err,
		"LastUpdated": latestUpdate,
	})
}

func getQuotesData() ([]*quotes.Quote, error) {
	client := http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsconfig.MTLSClientConfig(x509Src, bundleSrc, tlsconfig.AuthorizeID(quotesProviderSpiffeID)),
		},
	}

	resp, err := client.Get(quotesURL)
	if err != nil {
		log.Printf("Error getting quotes: %v", err)
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		log.Printf("Quotes unavailables: %s", resp.Status)
		return nil, err
	}

	jsonData, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Printf("Error reading response body: %v", err)
		return nil, err
	}

	data := []*quotes.Quote{}
	err = json.Unmarshal(jsonData, &data)
	if err != nil {
		log.Printf("Error unmarshaling json quotes: %v", err)
		return nil, err
	}

	return data, nil
}
