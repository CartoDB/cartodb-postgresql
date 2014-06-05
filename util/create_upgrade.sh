#!/bin/sh

fromver=$1
ver=$2
input=cartodb--${ver}.sql
output=cartodb--${fromver}--${ver}.sql

cat ${input} | grep -v 'duplicated extension$' > ${output}

