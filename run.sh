#!/bin/bash

#set -e

NCORE=8

# make top dirs
mkdir -p csd

# set variables
dwi=$(jq -r .dwi config.json)
bvecs=`jq -r '.bvecs' config.json`
bvals=`jq -r '.bvals' config.json`
anat=`jq -r '.anat' config.json`
brainmask=`jq -r '.brainmask' config.json`
mask=`jq -r '.mask' config.json`
IMAXS=`jq -r '.lmax' config.json`
premask=`jq -r '.premask' config.json`
NORM=`jq -r '.norm' config.json`

# convert dwi to mrtrix format
[ ! -f dwi.b ] && mrconvert -fslgrad $bvecs $bvals $dwi dwi.mif --export_grad_mrtrix dwi.b -nthreads $NCORE

difm='dwi'

# convert anat
[ ! -f t1.mif ] && mrconvert ${anat} t1.mif -nthreads $NCORE

anat='t1'

# convert 5tt mask
if [ -f ${mask} ]; then
	[ ! -f 5tt.mif ] && mrconvert ${mask} 5tt.mif -nthreads $NCORE
else
	5ttgen fsl ${anat}.mif 5tt.mif -nocrop -sgm_amyg_hipp -tempdir ./tmp -force $([ "$PREMASK" == "true" ] && echo "-premasked") -nthreads $NCORE -quiet
fi

# create mask of dwi
if [ ! -f mask.mif ]; then
	if [[ ${brainmask} == 'null' ]]; then
		[ ! -f mask.mif ] && dwi2mask dwi.mif mask.mif -nthreads $NCORE
	else
		echo "brainmask input exists. converting to mrtrix format"
		mrconvert ${brainmask} -stride 1,2,3,4 mask.mif -force -nthreads $NCORE
	fi
fi

mask='mask'

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

## print the # of b0s
echo Number of b0s: $NB0s 

## extract the shells and # of volumes per shell
BVALS=`mrinfo -shell_bvalues ${difm}.mif`
COUNTS=`mrinfo -shell_sizes ${difm}.mif`

## echo basic shell count summaries
echo -n "Shell b-values: "; echo $BVALS
echo -n "Unique Counts:  "; echo $COUNTS

## echo max lmax per shell
MLMAXS=`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
echo -n "Maximum Lmax:   "; echo $MLMAXS

## find maximum lmax that can be computed within data
MAXLMAX=`echo "$MLMAXS" | tr " " "\n" | sort -nr | head -n1`
echo "Maximum Lmax across shells: $MAXLMAX"

## if input $IMAXS is empty, set to $MAXLMAX
if [ ${IMAXS} == 'null' ]; then
    echo "No Lmax values requested."
    echo "Using the maximum Lmax of $MAXLMAX by default."
    IMAXS=$MAXLMAX
fi

## check if more than 1 lmax passed
NMAX=`echo $IMAXS | wc -w`

## find max of the requested list
if [ $NMAX -gt 1 ]; then

    ## pick the highest
    MMAXS=`echo -n "$IMAXS" | tr " " "\n" | sort -nr | head -n1`
    echo "User requested Lmax(s) up to: $MMAXS"
    LMAXS=$IMAXS
else
    MMAXS=$IMAXS
fi

## make sure requested Lmax is possible - fix if not
if [ $MMAXS -gt $MAXLMAX ]; then
    
    echo "Requested maximum Lmax of $MMAXS is too high for this data, which supports Lmax $MAXLMAX."
    echo "Setting maximum Lmax to maximum allowed by the data: Lmax $MAXLMAX."
    MMAXS=$MAXLMAX

fi

## create the list of the ensemble lmax values
if [ $NMAX -eq 1 ]; then
    
    ## create array of lmaxs to use
    emax=0
    LMAXS=''
	
    ## while less than the max requested
    while [ $emax -lt $MMAXS ]; do

	## iterate
	emax=$(($emax+2))
	LMAXS=`echo -n $LMAXS; echo -n ' '; echo -n $emax`

    done

else

    ## or just pass the list on
    LMAXS=$IMAXS

fi

## create the correct length of lmax
if [ $NB0s -eq 0 ]; then
    RMAX=${MAXLMAX}
else
    RMAX=0
fi
iter=1

## for every shell (after starting w/ b0), add the max lmax to estimate
while [ $iter -lt $(($NSHELL+1)) ]; do
    
    ## add the $MAXLMAX to the argument
    RMAX=$RMAX,$MAXLMAX

    ## update the iterator
    iter=$(($iter+1))

done

# extract mask
[ ! -f dt.mif ] && dwi2tensor -mask mask.mif dwi.mif dt.mif -bvalue_scaling false -force -nthreads $NCORE

#creating response (should take about 15min)
if [ $MS -eq 0 ]; then
	echo "Estimating CSD response function"
	time dwi2response tournier dwi.mif wmt.txt -lmax ${MAXLMAX} -force -nthreads $NCORE -tempdir ./tmp -quiet
else
	echo "Estimating MSMT CSD response function"
	time dwi2response msmt_5tt dwi.mif 5tt.mif wmt.txt gmt.txt csf.txt -mask mask.mif -lmax ${RMAX} -tempdir ./tmp -force -nthreads $NCORE -quiet
fi

# fitting CSD FOD of lmax
if [ $MS -eq 0 ]; then

    for lmax in $LMAXS; do

	echo "Fitting CSD FOD of Lmax ${lmax}..."
	time dwi2fod -mask ${mask}.mif csd ${difm}.mif wmt.txt wmt_lmax${lmax}_fod.mif -lmax $lmax -force -nthreads $NCORE -quiet

	## intensity normalization of CSD fit
	# if [ $NORM == 'true' ]; then
	#     #echo "Performing intensity normalization on Lmax $lmax..."
	#     ## function is not implemented for singleshell data yet...
	#     ## add check for fails / continue w/o?
	# fi
	
    done
    
else

    for lmax in $LMAXS; do

	echo "Fitting MSMT CSD FOD of Lmax ${lmax}..."
	time dwi2fod msmt_csd ${difm}.mif wmt.txt wmt_lmax${lmax}_fod.mif gmt.txt gmt_lmax${lmax}_fod.mif csf.txt csf_lmax${lmax}_fod.mif -mask ${mask}.mif -lmax $lmax,$lmax,$lmax -force -nthreads $NCORE -quiet

	if [ $NORM == 'true' ]; then

	   echo "Performing multi-tissue intensity normalization on Lmax $lmax..."
	   mtnormalise -mask ${mask}.mif wmt_lmax${lmax}_fod.mif wmt_lmax${lmax}_norm.mif gmt_lmax${lmax}_fod.mif gmt_lmax${lmax}_norm.mif csf_lmax${lmax}_fod.mif csf_lmax${lmax}_norm.mif -force -nthreads $NCORE -quiet

	   # check for failure / continue w/o exiting
	   if [ -z wmt_lmax${lmax}_norm.mif ]; then
	      echo "Multi-tissue intensity normalization failed for Lmax $lmax."
	      echo "This processing step will not be applied moving forward."
	      NORM='false'
	   fi

	fi

    done
    
fi

# convert to niftis
for lmax in $LMAXS; do
    
    if [ $NORM == 'true' ]; then
       mrconvert wmt_lmax${lmax}_norm.mif -stride 1,2,3,4 ./csd/lmax${lmax}.nii.gz -force -nthreads $NCORE -quiet
    else
       mrconvert wmt_lmax${lmax}_fod.mif -stride 1,2,3,4 ./csd/lmax${lmax}.nii.gz -force -nthreads $NCORE -quiet
    fi

done

# copy response file
[ ! -f ./csd/response.txt ] && cp wmt.txt ./csd/response.txt

# clean up
if [ -f ./csd/lmax${IMAXS}.nii.gz ]; then
        rm -rf *.mif* ./tmp *.b* *.txt*
else
        echo "csd generation failed"
        exit 1;
fi

echo "{\"tags\": [\"csd_${MAXLMAX}\" ]}" > product.json
