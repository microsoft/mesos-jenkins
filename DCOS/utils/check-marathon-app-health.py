#!/usr/bin/env python3

import argparse
import time

from dcos.marathon import create_client


def parse_parameters():
    parser = argparse.ArgumentParser(
        description="Verify if all the DCOS app tasks are healthy")
    parser.add_argument("-n", "--name", type=str, required=True,
                        help="The DCOS application name")
    parser.add_argument("--ignore-last-task-failure", action='store_true',
                        required=False, default=False, help="Flag to ignore"
                        "last task failure, used for recovery testing")
    return parser.parse_args()


def get_running_tasks(client, app_id, instances):
    timeout = 30 * 60
    print("Trying to find %s running tasks within a timeout of %s "
          "seconds." % (instances, timeout))
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
          "reported." % (task_id, timeout))
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
    healthy_tasks = []
    timeout = 40 * 60 * 1.0  # 40 minutes timeout
    start_time = time.time()
    while len(healthy_tasks) < app["instances"]:
        running_tasks = get_running_tasks(client, app["id"], app["instances"])
        for task in running_tasks:
            if task["id"] in healthy_tasks:
                continue
            print("Checking app health checks for task: %s" % task["id"])
            try:
                health_check_results = get_health_check_results(client,
                                                                task["id"])
            except Exception:
                print("Couldn't get health check results for "
                      "task %s" % (task["id"]))
                continue
            for result in health_check_results:
                if not result["alive"]:
                    raise Exception("Health checks for task %s didn't report "
                                    "successfully." % (task["id"]))
            healthy_tasks.append(task["id"])
            print("The health checks for task %s reported "
                  "successfully." % task["id"])
        current_time = time.time()
        if (current_time - start_time) > timeout:
            raise Exception("Couldn't get all the %s healthy tasks for "
                            "application %s within a %s seconds "
                            "timeout." % (app["instances"],
                                          app["id"],
                                          timeout))
    print("All the health checks for the application %s reported "
          "successfully." % (app["id"]))
    app = client.get_app(params.name)
    if not params.ignore_last_task_failure:
        if "lastTaskFailure" in app.keys():
            failure_message = app["lastTaskFailure"]["message"]
            raise Exception("Marathon reported last task failure. "
                            "Failure message: %s" % (failure_message))


if __name__ == '__main__':
    main()
