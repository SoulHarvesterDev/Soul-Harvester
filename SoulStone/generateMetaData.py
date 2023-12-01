#!/usr/bin/env python
# coding: utf-8

import time
import os
import json
from copy import deepcopy

import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)

# Preset

nrOfLevels = 10

# Base metadata. MUST BE EDITED.
BASE_IMAGE_URL = "ipfs://QmbMRuKiLjQ6kjdQ3qDS2YkY18cLXvg41byaCEReSnsXz5"
BASE_NAME = "Soul Stone Dummy"

BASE_JSON = {
    "name": BASE_NAME,
    "description": "There is something kept inside!",
    "external_url": "https://soulharvester.xyz",
    "image": BASE_IMAGE_URL
}


# Main function that generates the JSON metadata
def main():

    # Make json folder
    json_path = 'json'
    if not os.path.exists(json_path):
        os.makedirs(json_path)
    
    
    for idx in range(nrOfLevels):    
    
        # Get a copy of the base JSON (python dict)
        item_json = deepcopy(BASE_JSON)
        
        # Append image PNG file name to base image path
        item_json['image'] = item_json['image'] + '/' + str(idx + 1) + '.png'

        # Append level to json
        item_json['level'] = str(idx + 1)

        # Write file to json folder
        item_json_path = os.path.join(json_path, str(idx + 1) + '.json')
        with open(item_json_path, 'w') as f:
            json.dump(item_json, f)

# Run the main function
main()

# run "python generateMetaData.py" in terminal in the folder the file is in