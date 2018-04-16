package config

import "testing"

func TestConfigParse(t *testing.T) {

	testCfg := `
{"deployments":
  [
    {
      "cluster_definition":"examples/dcos-1.8.json",
      "location":"westus",
    },
    {
      "cluster_definition":"examples/dcos-1.9.json",
      "location":"eastus",
    },
    {
      "cluster_definition":"examples/dcos-1.10.json",
      "location":"southcentralus"
    },
    {
      "cluster_definition":"examples/dcos-1.11.json",
      "location":"westus2"
    }
  ]
}
`

	testConfig := TestConfig{}
	if err := testConfig.Read([]byte(testCfg)); err != nil {
		t.Fatal(err)
	}
	if err := testConfig.validate(); err != nil {
		t.Fatal(err)
	}
	if len(testConfig.Deployments) != 4 {
		t.Fatalf("Wrong number of deployments: %d instead of 4", len(testConfig.Deployments))
	}
}
