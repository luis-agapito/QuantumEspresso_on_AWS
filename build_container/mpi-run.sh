#!/bin/bash
echo "################################"
env
echo "################################"
#cd $JOB_DIR

PATH="$PATH:/usr/local/bin:/opt/openmpi/bin/"
BASENAME="${0##*/}"
log () {
  echo "${BASENAME} - ${1}"
}
HOST_FILE_PATH="/tmp/hostfile"
AWS_BATCH_EXIT_CODE_FILE="/tmp/batch-exit-code"

echo PATH: $PATH 
echo trying to download file from s3
aws --version
aws configure list
#aws s3 ls
#aws --debug s3 cp $S3_INPUT $SCRATCH_DIR/tmp.tar.gz
aws s3 cp $S3_INPUT $SCRATCH_DIR/tmp.tar.gz || echo "I could not bring gzip from s3"
tar -xvf $SCRATCH_DIR/tmp.tar.gz -C $SCRATCH_DIR
#$SCRATCH_DIR is "/scratch/"
#cp /tmp/Si.pz-vbc.UPF $SCRATCH_DIR
#cp /tmp/scf.in $SCRATCH_DIR

ls $SCRATCH_DIR

sleep 2

usage () {
  if [ "${#@}" -ne 0 ]; then
    log "* ${*}"
    log
  fi
  cat <<ENDUSAGE
Usage:
export AWS_BATCH_JOB_NODE_INDEX=0
export AWS_BATCH_JOB_NUM_NODES=10
export AWS_BATCH_JOB_MAIN_NODE_INDEX=0
export AWS_BATCH_JOB_ID=string
./mpi-run.sh
ENDUSAGE

  error_exit
}

# Standard function to print an error and exit with a failing return code
error_exit () {
  log "${BASENAME} - ${1}" >&2
  log "${2:-1}" > $AWS_BATCH_EXIT_CODE_FILE
  kill  $(cat /tmp/supervisord.pid)
}

# Check what environment variables are set
if [ -z "${AWS_BATCH_JOB_NODE_INDEX}" ]; then
  usage "AWS_BATCH_JOB_NODE_INDEX not set, unable to determine rank"
fi

if [ -z "${AWS_BATCH_JOB_NUM_NODES}" ]; then
  usage "AWS_BATCH_JOB_NUM_NODES not set. Don't know how many nodes in this job."
fi

if [ -z "${AWS_BATCH_JOB_MAIN_NODE_INDEX}" ]; then
  usage "AWS_BATCH_MULTI_MAIN_NODE_RANK must be set to determine the master node rank"
fi

NODE_TYPE="child"
if [ "${AWS_BATCH_JOB_MAIN_NODE_INDEX}" == "${AWS_BATCH_JOB_NODE_INDEX}" ]; then
  log "Running synchronize as the main node"
  NODE_TYPE="main"
fi

# Check that necessary programs are available
which aws >/dev/null 2>&1 || error_exit "Unable to find AWS CLI executable."


# wait for all nodes to report
wait_for_nodes () {
  log "Running as master node"

  touch $HOST_FILE_PATH
  ip=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
  if [ -x "$(command -v nvidia-smi)" ] ; then
      NUM_GPUS=$(ls -l /dev/nvidia[0-9] | wc -l)
      availablecores=$NUM_GPUS
  else
      availablecores=$(nproc)
  fi
  log "master details -> $ip:$availablecores"
  echo "$ip slots=$availablecores" >> $HOST_FILE_PATH

  lines=$(uniq $HOST_FILE_PATH|wc -l)
  while [ "$AWS_BATCH_JOB_NUM_NODES" -gt "$lines" ]
  do
    log "$lines out of $AWS_BATCH_JOB_NUM_NODES nodes joined, will check again in 10 second"
    sleep 10
    lines=$(uniq $HOST_FILE_PATH|wc -l)
  done
  # Make the temporary file executable and run it with any given arguments
  log "All nodes successfully joined"
  # remove duplicates if there are any.
  awk '!a[$0]++' $HOST_FILE_PATH > ${HOST_FILE_PATH}-deduped
  cat $HOST_FILE_PATH-deduped
  log "executing main MPIRUN workflow"

  #aws s3 cp $S3_INPUT $SCRATCH_DIR
  #tar -xvf $SCRATCH_DIR/*.tar.gz -C $SCRATCH_DIR

  echo "------------------------"
  cd $SCRATCH_DIR
  pwd
  ls -al $SCRATCH_DIR
  echo HOST_FILE_PATH
  cat ${HOST_FILE_PATH}
  echo HOST_FILE_PATH-deduped
  cat ${HOST_FILE_PATH}-deduped
  export OMP_NUM_THREADS=1
  /usr/lib64/openmpi/bin/mpirun --mca btl_tcp_if_include eth0 -np $MPI_THREADS  -N 1 \
                          -x PATH -x LD_LIBRARY_PATH -x OMP_NUM_THREADS \
                          --allow-run-as-root --machinefile ${HOST_FILE_PATH}-deduped \
                          --display-map --display-allocation \
                          /usr/local/bin/pw.x -inp scf.in > scf.out
  sleep 2
  ls -al $SCRATCH_DIR
  echo "------------------------"

  echo Compressing output files
  #tar -czvf $JOB_DIR/batch_output_$AWS_BATCH_JOB_ID.tar.gz $SCRATCH_DIR/*
  tar -czvf batch_output_$AWS_BATCH_JOB_ID.tar.gz $SCRATCH_DIR/*.out
  aws s3 cp batch_output_$AWS_BATCH_JOB_ID.tar.gz ${S3_OUTPUT}batch_output_$AWS_BATCH_JOB_ID.tar.gz  || echo Could not s3 cp 
  echo Uploaded output tar file 


  log "done! goodbye, writing exit code to $AWS_BATCH_EXIT_CODE_FILE and shutting down my supervisord"
  echo "0" > $AWS_BATCH_EXIT_CODE_FILE
  kill  $(cat /tmp/supervisord.pid)
  exit 0
}


# Fetch and run a script
report_to_master () {
  # looking for masters nodes ip address calling the batch API TODO
  # get own ip and num cpus
  #
  ip=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
  if [ -x "$(command -v nvidia-smi)" ] ; then
      NUM_GPUS=$(ls -l /dev/nvidia[0-9] | wc -l)
      availablecores=$NUM_GPUS
  else
      availablecores=$(nproc)
  fi
  log "I am a child node -> $ip:$availablecores, reporting to the master node -> ${AWS_BATCH_JOB_MAIN_NODE_PRIVATE_IPV4_ADDRESS}"
  until echo "$ip slots=$availablecores" | ssh ${AWS_BATCH_JOB_MAIN_NODE_PRIVATE_IPV4_ADDRESS} "cat >> /$HOST_FILE_PATH"
  do
    echo "Sleeping 5 seconds and trying again"
  done
  log "done! goodbye"
  exit 0
  }


# Main - dispatch user request to appropriate function
log $NODE_TYPE
case $NODE_TYPE in
  main)
    wait_for_nodes "${@}"
    ;;

  child)
    report_to_master "${@}"
    ;;

  *)
    log $NODE_TYPE
    usage "Could not determine node type. Expected (main/child)"
    ;;
esac
