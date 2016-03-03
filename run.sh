#!/bin/bash
ip=`ip a | grep global | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])'`
str=`date -Ins | md5sum`
name=${str:0:10}

elixir --name $name@$ip --cookie cookie -S mix