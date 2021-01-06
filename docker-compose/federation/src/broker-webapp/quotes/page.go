package quotes

import (
	"html/template"
	"log"
	"time"
)

const markup = `
<!DOCTYPE html>
<html>
    <head>

    </head>
    <body>
        <style>
            body {
                font-family: Arial, Helvetica, sans-serif;
                margin: 0 20%;
            }
            .right {
                text-align: right;
            }
            .center {
                text-align: center;
            }
            .quotes {
                width: 100%;
            }
            .quotes, .quotes td, .quotes th {
                border-spacing: 0;
                border: 1px solid black;
            }
            .error {
                color: red;
            }
        </style>
        {{if .Err}}
        <div class="error">Quotes service unavailable</div>
        {{end}}
        <table class="quotes">
            <caption class="right">Last Updated: {{.LastUpdated.Format "Jan 2 15:04:05"}}</caption>
            <thead>
                <tr>
                    <th scope="col">Symbol</th>
                    <th scope="col">Price</th>
                    <th scope="col">Open</th>
                    <th scope="col">Low</th>
                    <th scope="col">High</th>
                    <th scope="col">Close</th>
                    <th scope="col">Time</th>
                </tr>
            </thead>
			<tbody>
				{{range .Data}}
                <tr>
                    <th scope="row">{{.Symbol}}</th>
                    {{if .Time}}
                    <td class="right">{{.Price | printf "%.2f"}}</td>
                    <td class="right">{{.Open | printf "%.2f"}}</td>
                    <td class="right">{{.Low | printf "%.2f"}}</td>
                    <td class="right">{{.High | printf "%.2f"}}</td>
                    <td class="right">{{.Close | printf "%.2f"}}</td>
                    <td class="center">{{.Time.Format "15:04:05"}}</td>
                    {{else}}
                    <td class="right">-</td>
                    <td class="right">-</td>
                    <td class="right">-</td>
                    <td class="right">-</td>
                    <td class="right">-</td>
                    <td class="center">-</td>
                    {{end}}
                </tr>
                {{end}}
            </tbody>
        </table>
        <script>
            function refresh() {
                window.location.reload(true);
            }
            setTimeout(refresh, 1000);
        </script>        
    </body>
</html>
`

// Page is the quotes page template already parsed.
var Page *template.Template

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

func init() {
	var err error
	Page, err = template.New("quotes").Parse(markup)
	if err != nil {
		log.Fatal(err)
	}
}
