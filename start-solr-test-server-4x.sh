#!/bin/bash

set -e

# Redirect output to log files when stdin is not a TTY:
if [ ! -t 0 ]; then
    exec 1>test-solr.stdout.log 2>test-solr.stderr.log
fi

SOLR_VERSION=4.10.4

ROOT=$(cd `dirname $0`; pwd)
APP=$ROOT/solr-app
PIDS=$ROOT/solr.pids
export SOLR_ARCHIVE="${SOLR_VERSION}.tgz"
LOGS=$ROOT/logs
SIGNAL_STOP=-17
SIGNAL_START=-19


cd $ROOT

function download_solr() {
    if [ -d "${HOME}/download-cache/" ]; then
        export SOLR_ARCHIVE="${HOME}/download-cache/${SOLR_ARCHIVE}"
    fi

    if [ -f ${SOLR_ARCHIVE} ]; then
        # If the tarball doesn't extract cleanly, remove it so it'll download again:
        tar -tf ${SOLR_ARCHIVE} > /dev/null || rm ${SOLR_ARCHIVE}
    fi

    if [ ! -f ${SOLR_ARCHIVE} ]; then
        SOLR_DOWNLOAD_URL=$(python get-solr-download-url.py $SOLR_VERSION)
        curl -Lo $SOLR_ARCHIVE ${SOLR_DOWNLOAD_URL} || (echo "Unable to download ${SOLR_DOWNLOAD_URL}"; exit 2)
    fi
}

function extract_solr() {
    APP=solr-app
    echo "Extracting Solr ${SOLR_VERSION} to `pwd`/$APP"
    rm -rf $APP
    mkdir $APP
    tar -C $APP -xf ${SOLR_ARCHIVE} --strip-components 1 solr-${SOLR_VERSION}
}

function prepare_solr_home() {
    SOLR_HOME=$1
    HOST=$2
    echo "Preparing SOLR_HOME at $SOLR_HOME for host $HOST"
    APP=$(pwd)/solr-app
    mkdir -p ${SOLR_HOME}
    cp solr-app/example/solr/solr.xml ${SOLR_HOME}/
    cp solr-app/example/solr/zoo.cfg ${SOLR_HOME}/
}

function prepare_core() {
    SOLR_HOME=$1
    CORE=$2

    echo "Preparing core $CORE"

    CORE_DIR=${SOLR_HOME}/${CORE}
    mkdir -p ${CORE_DIR}

    cp -r solr-app/example/solr/collection1/conf ${CORE_DIR}/
    perl -p -i -e 's|<lib dir="../../../contrib/|<lib dir="$APP/contrib/|'g ${CORE_DIR}/conf/solrconfig.xml
    perl -p -i -e 's|<lib dir="../../../dist/|<lib dir="$APP/dist/|'g ${CORE_DIR}/conf/solrconfig.xml

    # Add MoreLikeThis handler
    perl -p -i -e 's|<!-- A Robust Example|<!-- More like this request handler -->\n  <requestHandler name="/mlt" class="solr.MoreLikeThisHandler" />\n\n\n  <!-- A Robust Example|'g ${CORE_DIR}/conf/solrconfig.xml

    echo "name=${CORE}" > ${CORE_DIR}/core.properties
}

function upload_configs() {
    ZKHOST=$1
    CONFIGS=$2
    APP=${ROOT}/solr-app

    echo "Uploading $CONFIGS configs to ZooKeeper at $ZKHOST"
    $APP/example/scripts/cloud-scripts/zkcli.sh -cmd upconfig -confdir ${CONFIGS} -confname config -zkhost ${ZKHOST} >> $LOGS/upload.log 2>&1
}

function wait_for() {
    NAME=$1
    PORT=$2
    COUNT=0
    echo -n "Waiting for ${NAME} to start on ${PORT}"
    while ! curl -s "http://localhost:${PORT}" > /dev/null; do
        echo -n '.'
        COUNT=$((COUNT+1))
        if [ $COUNT -gt 30 ]; then
            echo "Port ${PORT} not responding, quitting!"
            exit 1
        fi
        sleep 1
    done
    echo " done"
}

function create_collection() {
    PORT=$1
    COLLECTION=$2
    NODES=$3
    echo "Creating collection $COLLECTION on nodes $NODES"
    URL="http://localhost:${PORT}/solr/admin/collections?action=CREATE&name=${COLLECTION}&numShards=1&replicationFactor=2&collection.configName=config&createNodeSet=${NODES}"
    curl -s $URL > $LOGS/create-$COLLECTION.log
}

function start_solr() {
    SOLR_HOME=$1
    PORT=$2
    NAME=$3
    ARGS=$4
    echo > /dev/stderr
    echo "Starting server from ${SOLR_HOME} on port ${PORT}" > /dev/stderr
    # We use exec to allow process monitors to correctly kill the
    # actual Java process rather than this launcher script:
    export CMD="java -Djetty.port=${PORT} -Dsolr.install.dir=${APP} -Djava.awt.headless=true -Dapple.awt.UIElement=true -Dhost=localhost -Dsolr.solr.home=${SOLR_HOME} ${ARGS} -jar start.jar"
    pushd $APP/example > /dev/null

    exec $CMD >$LOGS/solr-$NAME.log &
    PID=$!
    echo $PID >> ${PIDS}

    popd > /dev/null
    echo "STARTED PORT $2 AS PID: ${PID}" > /dev/stderr
    echo $PID
}

function start_node() {
    PORT=$1
    NAME=$2
    echo "Starting ${NAME} on port ${PORT}"
    start_solr $ROOT/solr/${NAME} ${PORT} ${NAME} "-DzkHost=localhost:9992" > ${ROOT}/node-${PORT}.pid
}

function is_process_running() {
    PID=$1
    ps aux | awk '{print $2}' | tail -n +2 | grep -E "^${PID}$"
}

function stop_solr() {
    PORT=$1
    if [ "$PORT" != "" ]; then
        PID=$(cat ${ROOT}/node-${PORT}.pid)
        echo "Stopping ${PORT} - pid ${PID}"
        kill ${PID}
    elif [ -f $PIDS ]; then
        echo
        echo -n "Stopping Solr.."
        for PID in $(cat $PIDS); do
          if is_process_running $PID > /dev/null; then
            kill $PID
          else
            echo "Skipping $PID as it isn't running"
          fi
        done
        rm ${PIDS}
        rm -f ${ROOT}/node-*.pid
        echo " stopped"
    fi
}

function confirm_down() {
    NAME=$1
    PORT=$2

    if curl -s http://localhost:${PORT} > /dev/null 2>&1; then
        echo "Port ${PORT} for ${NAME} in use. Quitting."
        exit 1
    fi
}

function prepare() {
    if [ -f $PIDS ]; then
        echo "Found existing ${PIDS} file; stopping stale Solr instances"
        stop_solr
    fi

    rm -rf $APP
    rm -rf $ROOT/solr
    rm -rf $LOGS
    mkdir -p $LOGS

    echo "Preparing SOLR_HOME for tests at $ROOT/solr"
    download_solr
    extract_solr
    prepare_solr_home $ROOT/solr/non-cloud localhost
    prepare_core $ROOT/solr/non-cloud core0
    prepare_core $ROOT/solr/non-cloud core1
    prepare_solr_home $ROOT/solr/cloud-zk-node localhost_zk
    prepare_solr_home $ROOT/solr/cloud-node0 localhost_node0
    prepare_solr_home $ROOT/solr/cloud-node1 localhost_node1
    prepare_core $ROOT/solr/cloud-configs cloud
}

if [ $# -eq 0 ]; then
    echo "$0 [prepare] [start-simple] [start-cloud] [stop]"
    exit
fi

while [ $# -gt 0 ]; do
    if [ "$1" = "prepare" ]; then
        prepare
    elif [ "$1" = "stop" ]; then
        stop_solr
    elif [ "$1" = "stop-node" ]; then
        PORT=$2
        shift
        stop_solr $PORT
    elif [ "$1" = "start-node" ]; then
        PORT=$2
        NAME=$3
        shift 2
        start_node ${PORT} ${NAME}
    elif [ "$1" = "start" ]; then
        echo 'Starting Solr'
        confirm_down non-cloud 8983
        confirm_down cloud-zk 8992
        confirm_down cloud-node0 8993
        confirm_down cloud-node1 8994

        start_solr $ROOT/solr/cloud-zk-node 8992 zk -DzkRun
        wait_for ZooKeeper 8992
        upload_configs localhost:9992 $ROOT/solr/cloud-configs/cloud/conf
        start_solr $ROOT/solr/non-cloud 8983 non-cloud
        start_solr $ROOT/solr/cloud-node0 8993 cloud-node0 -DzkHost=localhost:9992 > ${ROOT}/node-8993.pid
        start_solr $ROOT/solr/cloud-node1 8994 cloud-node1 -DzkHost=localhost:9992 > ${ROOT}/node-8994.pid
        wait_for simple-solr 8983
        wait_for cloud-node0 8993
        wait_for cloud-node1 8994
        create_collection 8993 core0 localhost:8993_solr,localhost:8994_solr
        create_collection 8993 core1 localhost:8993_solr,localhost:8994_solr
        echo 'Solr started'
    else
        echo "Unknown command: $1"
        exit 1
    fi

    shift
done
