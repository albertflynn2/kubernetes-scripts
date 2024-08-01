#!/bin/bash

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for ns in $namespaces; do
  # Get all pods in the namespace
  pods=$(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}')

  for pod in $pods; do
    # Check the status of the pod
    status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')

    if [[ "$status" != "Running" && "$status" != "Succeeded" ]]; then
      echo "Pod $pod in namespace $ns is in $status state. Checking events for issues."

      # Get pod events
      events=$(kubectl get events --field-selector involvedObject.name=$pod -n $ns -o jsonpath='{range .items[*]}{.message}{"\n"}{end}')

      # Check for specific issues in events
      if echo "$events" | grep -q -E "Failed|Error|CrashLoopBackOff"; then
        echo "Issues found in events for pod $pod. Scaling up and down."

        # Get the deployment name
        deployment=$(kubectl get pod $pod -n $ns -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ReplicaSet")].name}' | sed 's/-[a-z0-9]*$//')

        if [ -n "$deployment" ]; then
          # Scale down to 0
          kubectl scale deployment $deployment -n $ns --replicas=0
          # Scale up to 1
          kubectl scale deployment $deployment -n $ns --replicas=1
        else
          echo "No deployment found for pod $pod in namespace $ns."
        fi
      else
        echo "No significant issues found in events for pod $pod."
      fi
    fi
  done

  # Check for issues with secrets
  secrets=$(kubectl get secrets -n $ns -o jsonpath='{.items[*].metadata.name}')
  for secret in $secrets; do
    if ! kubectl get secret $secret -n $ns &> /dev/null; then
      echo "Secret $secret in namespace $ns is missing or corrupted."
      # Add your secret recovery logic here
      # Example: Recreate the secret from a known good source
      kubectl create secret generic $secret --from-literal=key=value -n $ns
    fi
  done

  # Check for DNS issues
  dns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].metadata.name}')
  for dns_pod in $dns_pods; do
    dns_status=$(kubectl get pod $dns_pod -n kube-system -o jsonpath='{.status.phase}')
    if [[ "$dns_status" != "Running" ]]; then
      echo "DNS pod $dns_pod in namespace kube-system is in $dns_status state."
      # Add your DNS recovery logic here
      # Example: Restart the DNS pod
      kubectl delete pod $dns_pod -n kube-system
    fi
  done

  # Check for deployment issues
  deployments=$(kubectl get deployments -n $ns -o jsonpath='{.items[*].metadata.name}')
  for deployment in $deployments; do
    replicas=$(kubectl get deployment $deployment -n $ns -o jsonpath='{.status.replicas}')
    available_replicas=$(kubectl get deployment $deployment -n $ns -o jsonpath='{.status.availableReplicas}')
    if [[ "$replicas" -ne "$available_replicas" ]]; then
      echo "Deployment $deployment in namespace $ns has issues with replicas."
      # Add your deployment recovery logic here
      # Example: Rollout restart the deployment
      kubectl rollout restart deployment $deployment -n $ns
    fi
  done
done
