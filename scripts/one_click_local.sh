#tmp log dir
log_dir="$(mktemp -d /tmp/conflux_test_XXXXXX)"
echo $log_dir

python3 ../local_simulate.py --tmpdir $log_dir --num-nodes 12 --cluster-num 3 --nocleanup
python3 stat_latency_map_reduce.py $log_dir "$log_dir/blocks.log"

#find $log_dir -name conflux.log | xargs grep -i "thrott" > throttle.log
#find $log_dir -name conflux.log | xargs grep -i "error" > error.log
#find $log_dir -name conflux.log | xargs grep -i "txgen" > txgen.log
#find $log_dir -name conflux.log | xargs grep -i "packing" > tx_pack.log
#find $log_dir -name conflux.log | xargs grep -i "Partially invalid" > partially_invalid.log
#find $log_dir -name conflux.log | xargs grep -i "Sampled transaction" > tx_sample.log

python3 stat_latency.py localtest $log_dir "$log_dir/localtest.csv"
