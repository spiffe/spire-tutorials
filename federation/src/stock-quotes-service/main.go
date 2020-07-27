package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

const (
	port       = 8090
	socketPath = "unix:///tmp/agent.sock"
)

var (
	quotes = []*Quote{
		{Symbol: "AAAA"},
		{Symbol: "BBBB"},
		{Symbol: "CCCC"},
		{Symbol: "DDDD"},
		{Symbol: "EEEE"},
		{Symbol: "FFFF"},
		{Symbol: "GGGG"},
		{Symbol: "HHHH"},
		{Symbol: "IIII"},
		{Symbol: "JJJJ"},
		{Symbol: "KKKK"},
	}
	quotesMtx      = sync.RWMutex{}
	brokerSpiffeID = spiffeid.Must("broker.org", "webapp")
)

func main() {
	log.Print("Service waiting for an X.509 SVID...")

	ctx := context.Background()
	x509Src, err := workloadapi.NewX509Source(ctx,
		workloadapi.WithClientOptions(
			workloadapi.WithAddr(socketPath),
			//workloadapi.WithLogger(logger.Std),
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Service waiting for a trust bundle...")

	bundleSrc, err := workloadapi.NewBundleSource(ctx,
		workloadapi.WithClientOptions(
			workloadapi.WithAddr(socketPath),
		),
	)
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Addr:      fmt.Sprintf(":%d", port),
		TLSConfig: tlsconfig.MTLSServerConfig(x509Src, bundleSrc, tlsconfig.AuthorizeID(brokerSpiffeID)),
	}
	http.HandleFunc("/quotes", quotesHandler)

	log.Printf("Stock quotes service listening on port %d...", port)

	err = server.ListenAndServeTLS("", "")
	if err != nil {
		log.Fatal(err)
	}
}

// Quote represent a quote for a specific symbol in a specific time.
type Quote struct {
	Symbol string
	Price  float64
	Open   float64
	Low    float64
	High   float64
	Close  float64
	Time   *time.Time
}

func quotesHandler(resp http.ResponseWriter, req *http.Request) {
	randomizeQuotes()

	encoder := json.NewEncoder(resp)
	quotesMtx.RLock()
	err := encoder.Encode(quotes)
	quotesMtx.RUnlock()
	if err != nil {
		log.Printf("Error encoding data: %v", err)
		resp.WriteHeader(http.StatusInternalServerError)
		return
	}
}

func randomizeQuotes() {
	quotesMtx.Lock()
	for _, quote := range quotes {
		if rand.Int()%4 == 0 {
			priceDelta := rand.NormFloat64() * 1.5
			now := time.Now()
			if quote.Time == nil {
				quote.Open = priceDelta + 10 + 100*rand.Float64()
				quote.Low = quote.Open
				quote.High = quote.Open
				quote.Close = quote.Open - rand.NormFloat64()*1.5
				quote.Price = quote.Open
			} else {
				quote.Price += priceDelta
			}
			quote.Time = &now
			quote.Low = math.Min(quote.Price, quote.Low)
			quote.High = math.Max(quote.Price, quote.High)
		}
	}
	quotesMtx.Unlock()
}
