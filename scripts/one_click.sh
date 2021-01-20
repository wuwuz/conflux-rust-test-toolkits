#!/usr/bin/env bash
set -euxo pipefail

#if [ $# -lt 2 ]; then
#    echo "Parameters required: <key_pair> <instance_count> [<branch_name>] [<repository_url>] [<enable_flamegraph>] "
#    exit 1
#fi
key_pair="zhoumingxun"
slave_count=50
#slave_count=min($2)
#branch="${3:-master}"
#branch="${3:-coordinate}"
branch="${3:-highfanout}"
#repo="${4:-https://github.com/Conflux-Chain/conflux-rust}"
repo="${4:-https://github.com/wuwuz/conflux-rust}"
enable_flamegraph=${5:-false}
slave_role=${key_pair}_exp_slave

create_and_run=true

create_master=false
create_slave=$create_and_run
recompile=$create_and_run
run_exp=$create_and_run
download=$create_and_run
shut_slave=true
shut_master=false

nodes_per_host=4

run_latency_exp () {
    branch=$1
    exp_config=$2
    tps=$3
    max_block_size_in_bytes=$4

    #1) Create master instance and slave image
    if [ $create_master = true ]; then
        ./create_slave_image.sh $key_pair $branch $repo
        ./ip.sh --public
    fi

    #2) Launch slave instances

    master_ip=`cat ips`
    slave_image=`cat slave_image`

    # re-compile
    #ssh ubuntu@${master_ip} "cd ./conflux-rust/tests/extra-test-toolkits/scripts;export RUSTFLAGS=\"-g\" && cargo build --release ;"
    if [ $create_slave = true ]; then
        ssh ubuntu@${master_ip} "cd ./conflux-rust/tests/extra-test-toolkits/scripts;rm exp.log;rm -rf ~/.ssh/known_hosts;./launch-on-demand.sh $slave_count $key_pair $slave_role $slave_image;"
    fi

    # The images already have the compiled binary setup in `setup_image.sh`,
    # but we can use the following to recompile if we have code updated after image setup.
    #parallel-scp -O \"StrictHostKeyChecking no\" -h ips -l ubuntu -p 1000 ../../../target/release/conflux ~/conflux-rust/target/release/conflux |grep FAILURE|wc -l;" 
    if [ $recompile = true ]; then
        ssh ubuntu@${master_ip} "cd ./conflux-rust; git pull downstream ${branch}; git checkout ${branch}; git submodule update --init --recursive;"
        ssh ubuntu@${master_ip} "cd ./conflux-rust/tests/extra-test-toolkits/scripts;export RUSTFLAGS=-g && cargo build --release ; \
        parallel-scp -O \"StrictHostKeyChecking no\" -h ips -l ubuntu -p 1000 ../../../target/release/conflux ~ |grep FAILURE|wc -l;" 
        ssh ubuntu@${master_ip} "cd ./conflux-rust/tests/extra-test-toolkits/scripts; parallel-scp -O \"StrictHostKeyChecking no\" -h ips -l ubuntu -p 1000 throttle_bitcoin_bandwidth.sh remote_start_conflux.sh remote_collect_log.sh stat_latency_map_reduce.py  ~ |grep FAILURE|wc -l" 
    fi

    #TODO : add cp genesis_secrets.txt

    #4) Run experiments

    if [ $run_exp = true ]; then
        flamegraph_option=""
        if [ $enable_flamegraph = true ]; then
            flamegraph_option="--enable-flamegraph"
        fi
        ssh -tt ubuntu@${master_ip} "export PYTHONPATH=\${PYTHONPATH}:\${HOME}/conflux-rust/tests; cd ./conflux-rust/tests/extra-test-toolkits/scripts/; python3 exp_latency.py \
        --vms $slave_count \
        --batch-config \"$exp_config\" \
        --storage-memory-gb 16 \
        --bandwidth 20 \
        --tps $tps \
        --send-tx-period-ms 500 \
        $flamegraph_option \
        --nodes-per-host $nodes_per_host \
        --max-block-size-in-bytes $max_block_size_in_bytes \
        --enable-tx-propagation \
        --cluster-num 6 \
        --max-outgoing-peers 100 \
        --max-incoming-peers 100 \
        --fast-peer-local-group 5 \
        --min-peers-tx-propagation 8 \
        --max-peers-tx-propagation 8 \
        --first-hop-peers 200"
    fi

    #5) Terminate slave instances

    if [ $shut_slave = true ]; then
        rm -rf tmp_data
        mkdir tmp_data
        cd tmp_data
        ../list-on-demand.sh $slave_role || true
        ../terminate-on-demand.sh
        cd ..
    fi

    # Download results
    if [ $download = true ]; then
        archive_file="exp_stat_latency.tgz"
        log="exp_stat_latency.log"
        scp ubuntu@${master_ip}:~/conflux-rust/tests/extra-test-toolkits/scripts/${archive_file} .
        tar xfvz $archive_file
        cat $log
        mv $archive_file ${archive_file}.`date +%s`
        mv $log ${log}.`date +%s`
    fi
}

# Parameter for one experiment is <block_gen_interval_ms>:<txs_per_block>:<tx_size>:<num_blocks>
# Different experiments in a batch is divided by commas
# Example: "250:1:150000:1000,250:1:150000:1000,250:1:150000:1000,250:1:150000:1000"
exp_config="500:1:300000:1000"

# For experiments with --enable-tx-propagation , <txs_per_block> and <tx_size> will not take effects.
# Block size is limited by `max_block_size_in_bytes`.

tps=100
max_block_size_in_bytes=600000
echo "start run $branch"
run_latency_exp $branch $exp_config $tps $max_block_size_in_bytes

# Terminate master instance and delete slave images
# Comment this line if the data on the master instances are needed for further analysis

if [ $shut_master = true ]; then
    ./terminate-on-demand.sh
fi
