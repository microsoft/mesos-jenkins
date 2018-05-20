package main

import (
	"bufio"
	"bytes"
	"errors"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Microsoft/mesos-jenkins/DCOS/regression-testing/src/config"
	"github.com/Microsoft/mesos-jenkins/DCOS/regression-testing/src/metrics"
	"github.com/Microsoft/mesos-jenkins/DCOS/regression-testing/src/report"
)

const (
	script = "script/step.sh"

	stepInitAzure        = "set_azure_account"
	stepGetSecrets       = "get_secrets"
	stepCreateRG         = "create_resource_group"
	stepPredeploy        = "predeploy"
	stepGenerateTemplate = "generate_template"
	stepDeployTemplate   = "deploy_template"
	stepPostDeploy       = "postdeploy"
	stepValidate         = "validate"
	stepCleanup          = "cleanup"

	testReport     = "TestReport.json"
	combinedReport = "CombinedReport.json"

	metricsEndpoint = ":8125"
	metricsNS       = "ACSEngine"

	metricError              = "Error"
	metricDeploymentDuration = "DeploymentDuration"
	metricValidationDuration = "ValidationDuration"
)

const usage = `Usage:
  acs-engine-test <options>

  Options:
	-c <configuration.json> : JSON file containing a list of deployment configurations.
		Refer to acs-engine/test/acs-engine-test/acs-engine-test.json for examples
	-a <acs-engine root directory>
	-e <log-errors configuration file>
`

var (
	logDir        string
	enableMetrics bool
	subID         string
	rgPrefix      string
	orchestrator  string
)

// ErrorStat represents an error status that will be reported
type ErrorStat struct {
	errorInfo    *report.ErrorInfo
	testCategory string
	count        int64
}

// TestManager is object that contains test runner functions
type TestManager struct {
	config  *config.TestConfig
	Manager *report.Manager
	lock    sync.Mutex
	wg      sync.WaitGroup
	workDir string
}

// Run begins the test run process
func (m *TestManager) Run() error {
	n := len(m.config.Deployments)
	if n == 0 {
		return nil
	}

	// determine timeout
	timeoutMin, err := strconv.Atoi(os.Getenv("STAGE_TIMEOUT_MIN"))
	if err != nil {
		return fmt.Errorf("Error [Atoi STAGE_TIMEOUT_MIN]: %v", err)
	}
	timeout := time.Duration(time.Minute * time.Duration(timeoutMin))

	var retries int
	// determine number of retries
	retries, err = strconv.Atoi(os.Getenv("NUM_OF_RETRIES"))
	if err != nil {
		// Set default retries if not set
		retries = 1
	}
	fmt.Printf("Will allow %d retries to determine pass/fail\n", retries)

	// login to Azure
	if txt, _, err := m.runStep("init", stepInitAzure, os.Environ(), timeout); err != nil {
		return fmt.Errorf("Error [%s] %v : %s", stepInitAzure, err, txt)
	}

	// get secrets
	dataDir := filepath.Join(m.workDir, "_data")
	os.MkdirAll(dataDir, os.FileMode(0755))
	os.Setenv("DATA_DIR", dataDir)
	if txt, _, err := m.runStep("secrets", stepGetSecrets, os.Environ(), timeout); err != nil {
		return fmt.Errorf("Error [%s] %v : %s", stepGetSecrets, err, txt)
	}
	os.Setenv("SSH_KEY", filepath.Join(dataDir, "id_rsa.pub"))
	os.Setenv("WIN_PWD", filepath.Join(dataDir, "win.pwd"))

	// return values for tests
	success := make([]bool, n)
	rand.Seed(time.Now().UnixNano())

	m.wg.Add(n)
	for index, dep := range m.config.Deployments {
		go func(index int, dep config.Deployment) {
			defer m.wg.Done()
			resMap := make(map[string]*ErrorStat)
			for attempt := 0; attempt < retries; attempt++ {
				errorInfo := m.testRun(dep, index, attempt, timeout)
				// do not retry if successful
				if errorInfo == nil {
					success[index] = true
					break
				}
				if errorStat, ok := resMap[errorInfo.ErrName]; !ok {
					resMap[errorInfo.ErrName] = &ErrorStat{errorInfo: errorInfo, testCategory: dep.TestCategory, count: 1}
				} else {
					errorStat.count++
				}
			}

			sendErrorMetrics(resMap)
		}(index, dep)
	}
	m.wg.Wait()
	//create reports
	if err = m.Manager.CreateTestReport(fmt.Sprintf("%s/%s", logDir, testReport)); err != nil {
		fmt.Printf("Failed to create %s: %v\n", testReport, err)
	}
	// fail the test on error
	for _, ok := range success {
		if !ok {
			return errors.New("Test failed")
		}
	}
	return nil
}

func (m *TestManager) testRun(d config.Deployment, index, attempt int, timeout time.Duration) *report.ErrorInfo {
	subID = os.Getenv("SUBSCRIPTION_ID")

	rgPrefix = os.Getenv("RESOURCE_GROUP_PREFIX")
	if rgPrefix == "" {
		rgPrefix = "y"
		fmt.Printf("RESOURCE_GROUP_PREFIX is not set. Using default '%s'\n", rgPrefix)
	}

	testName := strings.TrimSuffix(d.ClusterDefinition, filepath.Ext(d.ClusterDefinition))
	instanceName := fmt.Sprintf("acse%d", rand.Intn(0x0ffffff))
	resourceGroup := fmt.Sprintf("%s-%s-%s-%s-%d-%d", rgPrefix, strings.Replace(testName, "/", "-", -1), d.Location, os.Getenv("BUILD_NUMBER"), index, attempt)
	logFile := fmt.Sprintf("%s/%s.log", logDir, resourceGroup)

	// determine orchestrator
	env := os.Environ()
	env = append(env, fmt.Sprintf("CLUSTER_DEFINITION=../cluster-defs/%s", d.ClusterDefinition))
	cmd := exec.Command(script, "get_orchestrator_type")
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		wrileLog(logFile, "Error [getOrchestrator %s] : %v", d.ClusterDefinition, err)
		return report.NewErrorInfo(testName, "pretest", "OrchestratorTypeParsingError", "PreRun", d.Location)
	}
	orchestrator = strings.TrimSpace(string(out))

	// update environment
	env = append(env, fmt.Sprintf("LOCATION=%s", d.Location))
	env = append(env, fmt.Sprintf("ORCHESTRATOR=%s", orchestrator))
	env = append(env, fmt.Sprintf("INSTANCE_NAME=%s", instanceName))
	env = append(env, fmt.Sprintf("DEPLOYMENT_NAME=%s", instanceName))
	env = append(env, fmt.Sprintf("RESOURCE_GROUP=%s", resourceGroup))
	if len(d.OrchestratorRelease) > 0 {
		env = append(env, fmt.Sprintf("ORCHESTRATOR_RELEASE=%s", d.OrchestratorRelease))
	}

	// add scenario-specific environment variables
	envFile := fmt.Sprintf("../cluster-defs/%s.env", d.ClusterDefinition)
	if _, err = os.Stat(envFile); err == nil {
		envHandle, err := os.Open(envFile)
		if err != nil {
			wrileLog(logFile, "Error [open %s] : %v", envFile, err)
			return report.NewErrorInfo(testName, "pretest", "FileAccessError", "PreRun", d.Location)
		}
		defer envHandle.Close()

		fileScanner := bufio.NewScanner(envHandle)
		for fileScanner.Scan() {
			str := strings.TrimSpace(fileScanner.Text())
			if match, _ := regexp.MatchString(`^\S+=\S+$`, str); match {
				env = append(env, str)
			}
		}
	}

	var errorInfo *report.ErrorInfo
	steps := []string{stepCreateRG, stepPredeploy, stepGenerateTemplate, stepDeployTemplate, stepPostDeploy, stepValidate}

	for _, step := range steps {
		txt, duration, err := m.runStep(resourceGroup, step, env, timeout)
		if err != nil {
			errorInfo = m.Manager.Process(txt, step, testName, d.Location)
			sendDurationMetrics(step, d.Location, duration, errorInfo.ErrName)
			wrileLog(logFile, "Error [%s:%s] %v\nOutput: %s", step, resourceGroup, err, txt)
			// check AUTOCLEAN flag: if set to 'n', don't remove deployment
			if os.Getenv("AUTOCLEAN") == "false" {
				env = append(env, "CLEANUP=false")
			}
			break
		}
		sendDurationMetrics(step, d.Location, duration, report.ErrSuccess)
		wrileLog(logFile, txt)
		if step == stepGenerateTemplate {
			// set up extra environment variables available after template generation
			cmd := exec.Command(script, "get_orchestrator_version")
			cmd.Env = env
			out, err := cmd.Output()
			if err != nil {
				wrileLog(logFile, "Error [%s:%s] %v\nOutput: %s", "get_orchestrator_version", resourceGroup, err, string(out))
				errorInfo = report.NewErrorInfo(testName, step, "OrchestratorVersionParsingError", "PreRun", d.Location)
				break
			}
			env = append(env, fmt.Sprintf("EXPECTED_ORCHESTRATOR_VERSION=%s", strings.TrimSpace(string(out))))

			cmd = exec.Command(script, "get_node_count")
			cmd.Env = env
			out, err = cmd.Output()
			if err != nil {
				wrileLog(logFile, "Error [%s:%s] %v", "get_node_count", resourceGroup, err)
				errorInfo = report.NewErrorInfo(testName, step, "NodeCountParsingError", "PreRun", d.Location)
				break
			}
			nodesCount := strings.Split(strings.TrimSpace(string(out)), ":")
			if len(nodesCount) != 3 {
				wrileLog(logFile, "get_node_count: unexpected output '%s'", string(out))
				errorInfo = report.NewErrorInfo(testName, step, "NodeCountParsingError", "PreRun", d.Location)
				break
			}
			env = append(env, fmt.Sprintf("EXPECTED_NODE_COUNT=%s", nodesCount[0]))
			env = append(env, fmt.Sprintf("EXPECTED_LINUX_AGENTS=%s", nodesCount[1]))
			env = append(env, fmt.Sprintf("EXPECTED_WINDOWS_AGENTS=%s", nodesCount[2]))
		}
	}
	// clean up
	if txt, _, err := m.runStep(resourceGroup, stepCleanup, env, timeout); err != nil {
		wrileLog(logFile, "Error [%s:%s] %v\nOutput: %s", stepCleanup, resourceGroup, err, txt)
	} else {
		wrileLog(logFile, txt)
	}
	return errorInfo
}

func isValidEnv() bool {
	valid := true
	envVars := []string{
		"SERVICE_PRINCIPAL_CLIENT_ID",
		"SERVICE_PRINCIPAL_CLIENT_SECRET",
		"TENANT_ID",
		"SUBSCRIPTION_ID",
		"STAGE_TIMEOUT_MIN",
		"JOB_BASE_NAME",
		"BUILD_NUMBER"}

	for _, envVar := range envVars {
		if os.Getenv(envVar) == "" {
			fmt.Printf("Must specify environment variable %s\n", envVar)
			valid = false
		}
	}
	return valid
}

func (m *TestManager) runStep(name, step string, env []string, timeout time.Duration) (string, time.Duration, error) {
	// prevent ARM throttling
	m.lock.Lock()
	go func() {
		time.Sleep(2 * time.Second)
		m.lock.Unlock()
	}()
	start := time.Now()
	cmd := exec.Command("/bin/bash", "-c", fmt.Sprintf("%s %s", script, step))
	cmd.Dir = m.workDir
	cmd.Env = env

	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	if err := cmd.Start(); err != nil {
		return "", time.Since(start), err
	}
	timer := time.AfterFunc(timeout, func() {
		cmd.Process.Kill()
	})
	err := cmd.Wait()
	timer.Stop()

	now := time.Now().Format("15:04:05")
	if err != nil {
		fmt.Printf("ERROR [%s] [%s %s]\n", now, step, name)
		return out.String(), time.Since(start), err
	}
	fmt.Printf("SUCCESS [%s] [%s %s]\n", now, step, name)
	return out.String(), time.Since(start), nil
}

func wrileLog(fname string, format string, args ...interface{}) {
	str := fmt.Sprintf(format, args...)

	f, err := os.OpenFile(fname, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Printf("Error [OpenFile %s] : %v\n", fname, err)
		return
	}
	defer f.Close()

	if _, err = f.Write([]byte(str)); err != nil {
		fmt.Printf("Error [Write %s] : %v\n", fname, err)
	}
}

func sendErrorMetrics(resMap map[string]*ErrorStat) {
	if !enableMetrics {
		return
	}
	for _, errorStat := range resMap {
		var severity string
		if errorStat.count > 1 {
			severity = "Critical"
		} else {
			severity = "Intermittent"
		}
		category := errorStat.testCategory
		if len(category) == 0 {
			category = "generic"
		}
		// add metrics
		dims := map[string]string{
			"TestName":     errorStat.errorInfo.TestName,
			"TestCategory": category,
			"Location":     errorStat.errorInfo.Location,
			"Error":        errorStat.errorInfo.ErrName,
			"Class":        errorStat.errorInfo.ErrClass,
			"Severity":     severity,
		}
		err := metrics.AddMetric(metricsEndpoint, metricsNS, metricError, errorStat.count, dims)
		if err != nil {
			fmt.Printf("Failed to send metric: %v\n", err)
		}
	}
}

func sendDurationMetrics(step, location string, duration time.Duration, errorName string) {
	if !enableMetrics {
		return
	}
	var metricName string

	switch step {
	case stepDeployTemplate:
		metricName = metricDeploymentDuration
	case stepValidate:
		metricName = metricValidationDuration
	default:
		return
	}

	durationSec := int64(duration / time.Second)
	// add metrics
	dims := map[string]string{
		"Location": location,
		"Error":    errorName,
	}
	err := metrics.AddMetric(metricsEndpoint, metricsNS, metricName, durationSec, dims)
	if err != nil {
		fmt.Printf("Failed to send metric: %v\n", err)
	}
}

func mainInternal() error {
	var configFile, logErrorFile, acsExePath string
	var err error

	flag.StringVar(&configFile, "c", "", "deployment configurations")
	flag.StringVar(&acsExePath, "a", "", "acs-engine exec path")
	flag.StringVar(&logErrorFile, "e", "acs-engine-errors.json", "logError config file")
	flag.Usage = func() {
		fmt.Println(usage)
	}
	flag.Parse()

	testManager := TestManager{}
	// set working directory
	testManager.workDir, err = filepath.Abs(filepath.Dir(os.Args[0]))
	if err != nil {
		return err
	}
	// validate environment
	if !isValidEnv() {
		return fmt.Errorf("environment is not set")
	}
	// get ace-engine exec
	if acsExePath == "" {
		return fmt.Errorf("acs-engine exec path is not provided")
	}
	if _, err = os.Stat(acsExePath); err != nil {
		return err
	}
	os.Setenv("ACS_ENGINE_EXE", acsExePath)
	// get test configuration
	if configFile == "" {
		return fmt.Errorf("test configuration is not provided")
	}
	testManager.config, err = config.GetTestConfig(configFile)
	if err != nil {
		return err
	}
	// set environment variable ENABLE_METRICS=y to enable sending the metrics (disabled by default)
	if os.Getenv("ENABLE_METRICS") == "y" {
		enableMetrics = true
	}

	// initialize report manager
	testManager.Manager = report.New(os.Getenv("JOB_BASE_NAME"), os.Getenv("BUILD_NUMBER"), len(testManager.config.Deployments), logErrorFile)

	if _, err = os.Stat(fmt.Sprintf("%s/%s", testManager.workDir, script)); err != nil {
		return err
	}
	// make logs directory
	logDir = fmt.Sprintf("%s/_logs", testManager.workDir)
	os.RemoveAll(logDir)
	if err = os.Mkdir(logDir, os.FileMode(0755)); err != nil {
		return err
	}
	return testManager.Run()
}

func main() {
	if err := mainInternal(); err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	os.Exit(0)
}
