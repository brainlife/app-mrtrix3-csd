[![Abcdspec-compliant](https://img.shields.io/badge/ABCD_Spec-v1.1-green.svg)](https://github.com/brain-life/abcd-spec)
[![Run on Brainlife.io](https://img.shields.io/badge/Brainlife-bl.app.239-blue.svg)](https://doi.org/10.25663/brainlife.app.239)

# app-mrtrix3-csd
This app will fit a csd with a user-inputted spherical harmonic order (lmax) using mrtrix3. This code was adapted from app-mrtrix3-act (https://brainlife.io/app/5aac2437f0b5260027e24ae1), written by Brent McPherson (bcmcpher@iu.edu).

### Authors
- Brent McPherson (bcmcpher@iu.edu)
- Brad Caron (bacaron@iu.edu)

### Contributors
- Soichi Hayashi (hayashi@iu.edu)

### Funding
[![NSF-BCS-1734853](https://img.shields.io/badge/NSF_BCS-1734853-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1734853)
[![NSF-BCS-1636893](https://img.shields.io/badge/NSF_BCS-1636893-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1636893)

## Running the App 

### On Brainlife.io

You can submit this App online at [https://doi.org/10.25663/brainlife.app.239](https://doi.org/10.25663/brainlife.app.239) via the "Execute" tab.

### Running Locally (on your machine)

1. git clone this repo.
2. Inside the cloned directory, create `config.json` with something like the following content with paths to your input files.

```json
{
  "dwi": "test/data/dwi/dwi.nii.gz",
  "bvals": "test/data/dwi/dwi.bvals",
  "bvecs": "test/data/dwi/dwi.bvecs",
  "brainmask": "test/data/mask/mask.nii.gz",
  "lmax": 8
}

```

### Sample Datasets

You can download sample datasets from Brainlife using [Brainlife CLI](https://github.com/brain-life/cli).

```
npm install -g brainlife
bl login
mkdir input
bl dataset download 5b96bbbf059cf900271924f2 && mv 5b96bbbf059cf900271924f2 input/t1
```


3. Launch the App by executing `main`

```bash
./main
```

## Output

The main output of this App is a mask datatype containing the 5tt mask.

#### Product.json
The secondary output of this app is `product.json`. This file allows web interfaces, DB and API calls on the results of the processing. 

### Dependencies

This App requires the following libraries when run locally.

  - singularity: https://singularity.lbl.gov/
  - Mrtrix3: https://hub.docker.com/r/brainlife/mrtrix3:3.0_RC3
