#!/bin/bash

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for ns in $namespaces; do
  # Get all pods in the namespace
  pods=$(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}')

  for pod in $pods; do
    # Check the status of the pod
    status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')

    if [ "$status" != "Running" ] && [ "$status" != "Succeeded" ]; then
      echo "Pod $pod in namespace $ns is in $status state. Checking events for issues."

      # Get pod events
      events=$(kubectl get events --field-selector involvedObject.name=$pod -n $ns -o jsonpath='{range .items[*]}{.message}{"\n"}{end}')

      # Check for specific issues in events
      if echo "$events" | grep -q -E "Failed|Error|CrashLoopBackOff|Pending|Unknown"; then
        echo "Issues found in events for pod $pod. Scaling up and down."

        # Get the deployment name
        deployment=$(kubectl get pod $pod -n $ns -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ReplicaSet")].name}' | sed 's/-[a-z0-9]*$//')

        if [ -n "$deployment" ]; then
          # Scale down to 0
          if ! kubectl scale deployment $deployment -n $ns --replicas=0; then
            echo "Failed to scale down deployment $deployment in namespace $ns."
            continue
          fi

          # Scale up to 1
          if ! kubectl scale deployment $deployment -n $ns --replicas=1; then
            echo "Failed to scale up deployment $deployment in namespace $ns."
            continue
          fi

          # Check if scaling succeeded
          sleep 10
          new_status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')
          if [ "$new_status" != "Running" ]; then
            echo "Scaling failed for pod $pod. Terminating and restarting."

            # Terminate the pod
            if ! kubectl delete pod $pod -n $ns; then
              echo "Failed to delete pod $pod in namespace $ns."
              continue
            fi

            # Restart the deployment
            if ! kubectl rollout restart deployment $deployment -n $ns; then
              echo "Failed to restart deployment $deployment in namespace $ns."
              continue
            fi
          fi
        else
          echo "No deployment found for pod $pod in namespace $ns."
        fi
      else
        echo "No significant issues found in events for pod $pod."
      fi
    fi
  done
done
