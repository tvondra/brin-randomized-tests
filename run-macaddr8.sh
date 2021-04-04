#!/bin/bash

DBNAME=macaddr8
QUERIES=$1
ROWS=$2

dropdb --if-exists $DBNAME
createdb $DBNAME

psql $DBNAME < random.sql

fillfactor=`psql $DBNAME -t -A -c "select (10 + random() * 90)::int"`
rangesize=`psql $DBNAME -t -A -c "select (1 + random() * 127)::int"`
nrows=$ROWS
nqueries=$QUERIES

# prefix is between 10 and 14 characters
prefixlen=`psql $DBNAME -t -A -c "select 8 + (mod((random() * 1000)::int, 7))"`

# prefix
prefix=`psql $DBNAME -t -A -c "select substr(md5(random()::text), 1, $prefixlen)"`

echo "prefix:" $prefix "(" $prefixlen ")"

suffix=$DBNAME

psql $DBNAME -c "create table t (a macaddr8) with (fillfactor = $fillfactor)";
psql $DBNAME -c "insert into t select random_macaddr8('$prefix') from generate_series(1,$nrows) s(i)";
psql $DBNAME -c "create index on t using brin (a macaddr8_minmax_multi_ops) with (pages_per_range = $rangesize)";

psql $DBNAME -t -A -c "select a from t order by random() limit $nqueries" > macaddr8.txt 2>&1;

c=0
while IFS= read -r line
do

    if [ -f "stop" ]; then
        echo "FAILED"; exit 1;
    fi

    v=$line

    psql -t -A $DBNAME >> seqscan-$suffix.log 2>&1 <<EOF
set enable_bitmapscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$v';
select count(*) from t where a = '$v';
EOF

    psql -t -A $DBNAME >> bitmapscan-$suffix.log 2>&1 <<EOF
set enable_seqscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$v';
select count(*) from t where a = '$v';
EOF

    s=`tail -n 1 seqscan-$suffix.log`
    b=`tail -n 1 bitmapscan-$suffix.log`

    c=$((c+1))
    echo $c $v $s $b

    if [ "$s" != "$b" ]; then
        echo "FAILED"; exit 1;
    fi

    v=`psql -t -A $DBNAME -c "select replace('$v', ':', '')"`

    x=`psql -t -A $DBNAME -c "select to_hex(x'$v'::bigint + 1)::macaddr8"`

    psql -t -A $DBNAME >> seqscan-$suffix.log 2>&1 <<EOF
set enable_bitmapscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$x';
select count(*) from t where a = '$x';
EOF

    psql -t -A $DBNAME >> bitmapscan-$suffix.log 2>&1 <<EOF
set enable_seqscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$x';
select count(*) from t where a = '$x';
EOF

    s=`tail -n 1 seqscan-$suffix.log`
    b=`tail -n 1 bitmapscan-$suffix.log`

    c=$((c+1))
    echo $c $x $s $b

    if [ "$s" != "$b" ]; then
        echo "FAILED"; exit 1;
    fi

    x=`psql -t -A $DBNAME -c "select to_hex(x'$v'::bigint - 1)::macaddr8"`

    psql -t -A $DBNAME >> seqscan-$suffix.log 2>&1 <<EOF
set enable_bitmapscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$x';
select count(*) from t where a = '$x';
EOF

    psql -t -A $DBNAME >> bitmapscan-$suffix.log 2>&1 <<EOF
set enable_seqscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$x';
select count(*) from t where a = '$x';
EOF

    s=`tail -n 1 seqscan-$suffix.log`
    b=`tail -n 1 bitmapscan-$suffix.log`

    c=$((c+1))
    echo $c $x $s $b

    if [ "$s" != "$b" ]; then
        echo "FAILED"; exit 1;
    fi

done < macaddr8.txt

for i in `seq 1 $nqueries`; do

    if [ -f "stop" ]; then
        echo "FAILED"; exit 1;
    fi

    v=`psql -t -A $DBNAME -c "select substr(md5(random()::text),1,12)::macaddr8"`

    psql -t -A $DBNAME >> seqscan-$suffix.log 2>&1 <<EOF
set enable_bitmapscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$v';
select count(*) from t where a = '$v';
EOF

    psql -t -A $DBNAME >> bitmapscan-$suffix.log 2>&1 <<EOF
set enable_seqscan = off;
set enable_indexscan = off;
set max_parallel_workers_per_gather = 0;
explain select count(*) from t where a = '$v';
select count(*) from t where a = '$v';
EOF

    s=`tail -n 1 seqscan-$suffix.log`
    b=`tail -n 1 bitmapscan-$suffix.log`

    c=$((c+1))
    echo $c $v $s $b

    if [ "$s" != "$b" ]; then
        echo "FAILED"; exit 1;
    fi

done

echo "SUCCESS";
dropdb $DBNAME;
