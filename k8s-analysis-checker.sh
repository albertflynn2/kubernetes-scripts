#!/bin/bash

# Get the script name without the path
script_name=$(basename "$0")

# Get the current date and time
current_date=$(date +%Y-%m-%d_%H-%M-%S)

# Create a log file with the script name and date
log_file="${script_name%.sh}_$current_date.log"

# Function to log messages
log_message() {
  local message="$1"
  echo "$message" | tee -a "$log_file"
}

# Function to check command success
check_command_success() {
  if [ $? -ne 0 ]; then
    log_message "Error: $1"
    exit 1
  fi
}

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
check_command_success "Failed to get namespaces"

for ns in $namespaces; do
  log_message "Processing namespace: $ns"

  # Get all pods in the namespace
  pods=$(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}')
  check_command_success "Failed to get pods in namespace $ns"

  for pod in $pods; do
    # Check the status of the pod
    status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')
    check_command_success "Failed to get status for pod $pod in namespace $ns"

    if [ "$status" != "Running" ] && [ "$status" != "Succeeded" ]; then
      log_message "Pod $pod in namespace $ns is in $status state. Checking events for issues."

      # Get pod events
      events=$(kubectl get events --field-selector involvedObject.name=$pod -n $ns -o jsonpath='{range .items[*]}{.message}{"\n"}{end}')
      check_command_success "Failed to get events for pod $pod in namespace $ns"

      # Check for specific issues in events
      if echo "$events" | grep -q -E "Failed|Error|CrashLoopBackOff"; then
        log_message "Issues found in events for pod $pod. Possible causes: resource limits, configuration errors, or image issues."
      else
        log_message "No significant issues found in events for pod $pod."
      fi
    fi

    # Gather additional information
    log_message "Gathering additional information for pod $pod in namespace $ns."

    # Get node information
    node=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}')
    check_command_success "Failed to get node information for pod $pod in namespace $ns"
    log_message "Pod $pod is running on node $node."

    # Get CPU and memory usage
    kubectl top pod $pod -n $ns --containers &> /dev/null
    if [ $? -eq 0 ]; then
      cpu_usage=$(kubectl top pod $pod -n $ns --containers | awk 'NR>1 {print $2}')
      memory_usage=$(kubectl top pod $pod -n $ns --containers | awk 'NR>1 {print $3}')
      log_message "CPU usage for pod $pod: $cpu_usage"
      log_message "Memory usage for pod $pod: $memory_usage"
    else
      log_message "Failed to get resource usage for pod $pod in namespace $ns"
    fi

    # Get container image information
    images=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].image}')
    check_command_success "Failed to get images for pod $pod in namespace $ns"
    log_message "Images used in pod $pod: $images"

    # Get connections information
    connections=$(kubectl exec $pod -n $ns -- netstat -tuln 2>/dev/null || kubectl exec $pod -n $ns -- ss -tuln 2>/dev/null || echo "Failed to retrieve connections information")
    log_message "Connections for pod $pod: $connections"
  done
done

# Get node-level information
log_message "Gathering node-level information."

nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
check_command_success "Failed to get nodes information"

for node in $nodes; do
  log_message "Node: $node"
  cpu_allocatable=$(kubectl get node $node -o jsonpath='{.status.allocatable.cpu}')
  memory_allocatable=$(kubectl get node $node -o jsonpath='{.status.allocatable.memory}')
  log_message "CPU allocatable: $cpu_allocatable"
  log_message "Memory allocatable: $memory_allocatable"
done

log_message "Script execution completed."
