#!/bin/bash

set -e

NCORE=8

# make top dirs
mkdir -p csd

# set variables
dwi=$(jq -r .dwi config.json)
bvecs=`jq -r '.bvecs' config.json`
bvals=`jq -r '.bvals' config.json`
brainmask=`jq -r '.brainmask' config.json`
LMAX=`jq -r '.lmax' config.json`

# convert dwi to mrtrix format
[ ! -f dwi.b ] && mrconvert -fslgrad $bvecs $bvals $dwi dwi.mif --export_grad_mrtrix dwi.b -nthreads $NCORE

# create mask of dwi
if [[ ${brainmask} == 'null' ]]; then
	[ ! -f mask.mif ] && dwi2mask dwi.mif mask.mif -nthreads $NCORE
else
	echo "brainmask input exists. converting to mrtrix format"
	mrconvert ${brainmask} -stride 1,2,3,4 mask.mif -force -nthreads $NCORE
fi

# extract b0 image from dwi
[ ! -f b0.mif ] && dwiextract dwi.mif - -bzero | mrmath - mean b0.mif -axis 3 -nthreads $NCORE

# check if b0 volume successfully created
if [ ! -f b0.mif ]; then
    echo "No b-zero volumes present."
    NSHELL=`mrinfo -shell_bvalues dwi.mif | wc -w`
    NB0s=0
    EB0=''
else
    ISHELL=`mrinfo -shell_bvalues dwi.mif | wc -w`
    NSHELL=$(($ISHELL-1))
    NB0s=`mrinfo -shell_sizes dwi.mif | awk '{print $1}'`
    EB0="0,"
fi

## determine single shell or multishell fit
if [ $NSHELL -gt 1 ]; then
    MS=1
    echo "Multi-shell data: $NSHELL total shells"
else
    echo "Single-shell data: $NSHELL shell"
    MS=0
    if [ ! -z "$TENSOR_FIT" ]; then
	echo "Ignoring requested tensor shell. All data will be fit and tracked on the same b-value."
    fi
fi

## create the correct length of lmax
if [ $NB0s -eq 0 ]; then
    RMAX=${LMAX}
else
    RMAX=0
fi
iter=1

## for every shell (after starting w/ b0), add the max lmax to estimate
while [ $iter -lt $(($NSHELL+1)) ]; do
    
    ## add the $MAXLMAX to the argument
    RMAX=$RMAX,$LMAX

    ## update the iterator
    iter=$(($iter+1))

done

# extract mask
[ ! -f dt.mif ] && dwi2tensor -mask mask.mif dwi.mif dt.mif -bvalue_scaling false -force -nthreads $NCORE

#creating response (should take about 15min)
if [ $MS -eq 0 ]; then
	echo "Estimating CSD response function"
	time dwi2response tournier dwi.mif wmt.txt -lmax ${LMAX} -force -nthreads $NCORE -tempdir ./tmp
else
	echo "Estimating MSMT CSD response function"
	time dwi2response msmt_5tt dwi.mif 5tt.mif wmt.txt gmt.txt csf.txt -mask mask.mif -lmax ${RMAX} -tempdir ./tmp -force -nthreads $NCORE
fi

# fitting CSD FOD of lmax
if [ $MS -eq 0 ]; then
	echo "Fitting CSD FOD of Lmax ${LMAX}..."
	time dwi2fod -mask mask.mif csd dwi.mif wmt.txt wmt_lmax${LMAX}_fod.mif -lmax ${LMAX} -force -nthreads $NCORE
else
	echo "Estimating MSMT CSD FOD of Lmax ${LMAX}"
	time dwi2fod msmt_csd dwi.mif wmt.txt wmt_lmax${LMAX}_fod.mif  gmt.txt gmt_lmax${LMAX}_fod.mif csf.txt csf_lmax${LMAX}_fod.mif -force -nthreads $NCORE
fi

# convert to niftis
[ ! -f ./csd/lmax${LMAX}.nii.gz ] && mrconvert wmt_lmax${LMAX}_fod.mif -stride 1,2,3,4 ./csd/lmax${LMAX}.nii.gz -force -nthreads $NCORE

# copy response file
[ ! -f ./csd/response.txt ] && cp wmt.txt ./csd/response.txt

# clean up
if [ -f ./csd/csd.nii.gz ]; then
        rm -rf *.mif* ./tmp *.b*
else
        echo "csd generation failed"
        exit 1;
fi

echo "{\"tags\": [\"csd_${LMAX}\" ]}" > product.json
