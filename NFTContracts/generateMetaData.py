#!/usr/bin/env python
# coding: utf-8

import time
import os
import json
from copy import deepcopy

import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)

# Preset

nrOfNFTs = 50

# Base metadata. MUST BE EDITED.
BASE_IMAGE_URL = "ipfs://QmW12aPELteJTDHzmHpQtGMN9RBwrhJMvjaaFuTfNu7Fw5"
BASE_NAME = "Keeper of the Veil #"

BASE_JSON = {
    "name": BASE_NAME,
    "description": "The true believers and servants of the greater vision!",
    "external_url": "https://soulharvester.xyz",
    "image": BASE_IMAGE_URL
}


# Main function that generates the JSON metadata
def main():

    # Make json folder
    json_path = 'json'
    if not os.path.exists(json_path):
        os.makedirs(json_path)
    
    
    for idx in range(nrOfNFTs):    
    
        # Get a copy of the base JSON (python dict)
        item_json = deepcopy(BASE_JSON)
        
        # Append number to base name
        item_json['name'] = item_json['name'] + str(idx + 1)

        # Append image PNG file name to base image path
        item_json['image'] = item_json['image'] + '/' + str(idx + 1) + '.png'
        
        # Write file to json folder
        item_json_path = os.path.join(json_path, str(idx + 1) + '.json')
        with open(item_json_path, 'w') as f:
            json.dump(item_json, f)

# Run the main function
main()

# run "python generateMetaData.py" in terminal in the folder the file is in