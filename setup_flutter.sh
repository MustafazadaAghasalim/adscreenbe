#!/bin/bash

# Create development directory
mkdir -p ~/development
cd ~/development

# Clone Flutter if it doesn't exist
if [ ! -d "flutter" ]; then
    echo "Downloading Flutter SDK (this may take a few minutes)..."
    git clone https://github.com/flutter/flutter.git -b stable
else
    echo "Flutter SDK found in ~/development/flutter"
fi

# Add to PATH for this session
export PATH="$PATH:$HOME/development/flutter/bin"

# Run doctor to finish setup
echo "Running Flutter Doctor to complete installation..."
flutter doctor

echo "Flutter setup complete!"
