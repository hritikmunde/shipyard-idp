#!/bin/bash
echo "🗑️  Tearing down Shipyard IDP..."
kind delete cluster --name shipyard
echo "✅ Done"