#!/bin/bash

#running blockMesh and sHM and writing everything to log files

runnr=$1
session_log=logs/$runnr/run_$runnr.log

#--------------------------------------------------------------
# An error exit function

error_exit()
{
	echo -e "$1" 2>&1 | tee -a $session_log
	exit 1
}

#--------------------------------------------------------------
#

check_result()
{
	echo " "
	grep -w "Failed" logs/$runnr/$1"_"$runnr.log | tee -a $session_log
	echo "----------------" | tee -a $session_log
	grep '^\ \*\*\*' logs/$runnr/$1"_"$runnr.log | tee -a $session_log
	echo -e "----------------\n" | tee -a $session_log
}

#--------------------------------------------------------------
#

block_mesh()
{
	# create new blockMesh
	echo -e "*****\ncreating new blockMesh...\n" | tee -a $session_log

	rm -f constant/polyMesh/* > /dev/null 2>&1
	{ time blockMesh > logs/$runnr/bM_$runnr.log ; } 2>&1 | tee -a $session_log || error_exit "blockMesh did not complete! Aborting\n" | tee -a $session_log

	echo -e "\n...and checking it...\n" | tee -a $session_log

	{ time checkMesh -allGeometry -allTopology > logs/$runnr/cMbM_$runnr.log ; } 2>&1 | tee -a $session_log

	check_result "cMbM"

	echo "Mesh stats: " | tee -a $session_log
	grep '    cells:' logs/$runnr/cMbM_$runnr.log | tee -a $session_log
	echo " "
}

#--------------------------------------------------------------

echo "
###############################################################
#----------- Starting meshing run script (Run $runnr) -------------#
#-------------------------------------------------------------#
#----------------- Author: Jan Peters ------------------------#
###############################################################
" | tee $session_log

############################################################################################
# RUN CASE CONFIG
############################################################################################

# Create new run folder to store case and logs fro later analysis

if [ -d logs/$runnr ] 
then
    echo "Case directory $runnr does already exist, do you want to overwrite?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) rm -f logs/$runnr/*; break;; 
            No ) exit;;
        esac
    done
else
	mkdir logs/$runnr
fi

if [ -d logs/$runnr ] 
then
    echo -e "\nCreate a new blockMesh or skip and use an existing one?"
    select cs in "Create" "Skip"; do
        case $cs in
            Create ) blockmesh=1; break;; 
            Skip ) blockmesh=0; break;;
        esac
    done
fi

############################################################################################
# CLEANING THE CASE FOLDER
############################################################################################

# remove surface and features
echo -e "\n*****\nremoving previous case files and meshes...\n" | tee -a $session_log

rm -f 0/pointLevel > /dev/null 2>&1
rm -f 0/cellLevel > /dev/null 2>&1

if [ -d "1" ]
then
	rm -rf 1 > /dev/null 2>&1
fi
if [ -d "2" ]
then
	rm -rf 2 > /dev/null 2>&1
fi
if [ -d "3" ]
then
	rm -rf 3 > /dev/null 2>&1
fi

###########################################################################################
# BLOCKMESH & CHECKMESH
###########################################################################################

# create the blockMesh
if [ $blockmesh -eq 1 ]; then
	block_mesh
else
	echo -e "\nSkip blockMesh and use existing Mesh in constant/polyMesh\n"
fi

###########################################################################################
# FEATUREEXTRACT
###########################################################################################

# run Feature extract
echo -e "*****\ncreating surface feature eMesh file...\n" | tee -a $session_log

rm -rf constant/extendedFeatureEdgeMesh > /dev/null 2>&1
rm -f constant/triSurface/*.eMesh > /dev/null 2>&1
{ time surfaceFeatureExtract > logs/$runnr/sFE_$runnr.log ; } 2>&1 | tee -a $session_log

###########################################################################################
# SNAPPYHEXMESH & CHECKMESH
###########################################################################################

# make a copy of the snappyhexmesh dictionary file for later reference to the case setup
cp system/snappyHexMeshDict logs/$runnr/snappyDict_$runnr

# preparing for parallel meshing
echo -e "\n*****\nPreparing the case for meshing in parallel...\n" | tee -a $session_log
decomposePar 2>&1 > logs/$runnr/decomp_$runnr.log

# Run snappyHexMesh without overwrite to look at the single steps in Meshing
echo -e "\n*****\nrunning snappyHexMesh without overwrite to analyse the single steps...\n" | tee -a $session_log

{ time mpirun -np 8 snappyHexMesh -parallel > logs/$runnr/snappy_$runnr.log ; } 2>&1 | tee -a $session_log || error_exit "snappyHexMesh did not complete! Aborting\n" | tee -a $session_log

# putting the case back together
echo -e "\n*****\nMerging the mesh parts back together...\n" | tee -a $session_log
reconstructParMesh -time 1 -mergeTol 1e-06 -constant 2>&1 > logs/$runnr/merge_$runnr.log
reconstructParMesh -time 2 -mergeTol 1e-06 -constant 2>&1 >> logs/$runnr/merge_$runnr.log

# removing the processor folders created by the decompose step for parallel processing
echo -e "\n*****\nDeleting the processor folders...\n" | tee -a $session_log
rm -rf proc*

if [ -d "1" ]; then
	echo -e "*****\nchecking castellation phase in mesh generation...\n" | tee -a $session_log
	{ time checkMesh -allGeometry -allTopology -time 1 > logs/$runnr/scM1_$runnr.log ; } 2>&1 | tee -a $session_log || error_exit "checkMesh on Time 1 did not complete! Aborting\n" | tee -a $session_log
	check_result "scM1"
	echo "Mesh stats:" | tee -a $session_log
	grep '    cells:' logs/$runnr/scM1_$runnr.log | tee -a $session_log
	echo " "
else 
	echo -e "*****\nDirectory 1 not found!\n" | tee -a $session_log
fi

if [ -d "2" ]; then
	echo -e "*****\nchecking snapping phase in mesh generation...\n		"  | tee -a $session_log
	{ time checkMesh -allGeometry -allTopology -time 2 > logs/$runnr/scM2_$runnr.log ; } 2>&1 | tee -a $session_log || error_exit "checkMesh on Time 2 did not complete! Aborting\n" | tee -a $session_log
	check_result "scM2"	
else 
	echo -e "**\nDirectory 2 not found!\n" | tee -a $session_log
fi

if [ -d "3" ]; then
	echo -e "*****\nchecking layer phase in mesh generation...\n" | tee -a $session_log
	{ time checkMesh -allGeometry -allTopology -time 3 > logs/$runnr/scM3_$runnr.log ; } 2>&1 | tee -a $session_log || error_exit "checkMesh on Time 3 did not complete! Aborting\n" | tee -a $session_log
	check_result "scM3"
else 
	echo -e "*****\nDirectory 3 not found!\n" | tee -a $session_log
fi
