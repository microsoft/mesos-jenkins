#!/usr/bin/env python3

import argparse
import time

from dcos.marathon import create_client


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Verify if all the DCOS app tasks are healthy")
    parser.add_argument("-n", "--name", type=str, required=True,
                        help="The DCOS application name")
    return parser.parse_args()


def get_running_tasks(client, app_id, instances):
    timeout = 30 * 60
    print("Trying to find %s running tasks within a timeout of %s "
          "seconds timeout." % (instances, timeout))
    i = 0
    running_tasks = []
    while len(running_tasks) < instances:
        if i == timeout:
            break
        tasks = client.get_tasks(app_id)
        if len(tasks) == 0:
            time.sleep(1)
            i += 1
            continue
        for task in tasks:
            if task["state"] != "TASK_RUNNING":
                continue
            running_tasks.append(task)
        time.sleep(1)
        i += 1
    if len(running_tasks) < instances:
        raise Exception("There weren't at least %s running task spawned "
                        "within a timeout of %s seconds" % (instances,
                                                            timeout))
    return running_tasks


def get_health_check_results(client, task_id):
    task = client.get_task(task_id)
    if not task:
        raise Exception("Task %s doesn't exist anymore" % task_id)
    results_reported = "healthCheckResults" in task.keys()
    if results_reported:
        return task["healthCheckResults"]
    timeout = 120
    print("There are no health check results for the task %s. Waiting "
          "maximum %s seconds to see if health check results will be "
          "reported in the meantime." % (task_id, timeout))
    i = 0
    while not results_reported:
        task = client.get_task(task_id)
        if not task:
            raise Exception("Task %s doesn't exist anymore" % task_id)
        results_reported = "healthCheckResults" in task.keys()
        time.sleep(1)
        i += 1
        if i == timeout:
            break
    if not results_reported:
        raise Exception("There were no health checks reported for "
                        "task %s." % task_id)
    return task["healthCheckResults"]


def main():
    params = parse_parameters()
    client = create_client()
    app = client.get_app(params.name)
    if "healthChecks" not in app.keys():
        raise Exception("The application %s doesn't have health checks. "
                        "Cannot decide whether it's "
                        "healthy or not." % params.name)
    running_tasks = get_running_tasks(client, app["id"], app["instances"])
    for task in running_tasks:
        print("Checking app health checks for task: %s" % task["id"])
        health_check_results = get_health_check_results(client, task["id"])
        for result in health_check_results:
            if result["alive"]:
                continue
            if not health_check_results["alive"]:
                raise Exception("Health checks for task %s didn't report "
                                "successfully." % (task["id"]))
        print("The health checks for task %s reported "
              "successfully." % task["id"])
    print("All the health checks for the application %s reported "
          "successfully." % (app["id"]))


if __name__ == '__main__':
    main()
