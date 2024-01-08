#!/bin/bash
bucks=()
if [ "$1" != "" ]; then
    if [[ $1 != "*" ]];then
        bucks+=$($AWS s3api list-buckets --query Buckets[*].Name | jq -r .[] | grep $1)
    fi
else
    bucks+=$($AWS s3api list-buckets --query Buckets[*].Name | jq -r .[])
fi

if [ "$bucks" == "" ]; then
    echo "$ : You don't have access for this resource"
    exit
fi

ttft="aws_s3_bucket"
theregion=$(echo "var.region" | terraform console | tr -d '"')
keyid=""
doacl2=0
ncpu=$(getconf _NPROCESSORS_ONLN)
ncpu=`expr $ncpu \* 2`

skipbucks=()
bucklist=()

for cname in ${bucks[@]}; do
    #echo "getting bucket $cname"
    lifec=0
    doacl2=0

    if [ "$cname" != "null" ]; then
        rname=$(printf "b_%s" $cname)
        fn=`printf "%s__b_%s.tf" $ttft $cname`
        if [ -f "$fn" ]; then echo "$fn exists already skipping" && continue; fi

        # check region & access
        br=$($AWS s3api get-bucket-location --bucket ${cname})
        if [ $? -ne 0 ]; then
            br="none"
            echo "Cannot access buck $cname - skipping ..."
            continue
        else
            br=$(echo $br | jq .LocationConstraint | tr -d '"')
        fi

        if [[ "$br" == "$theregion" ]] || [[ $br == "null"  &&  "$theregion" == "us-east-1" ]]; then

            #echo "$ttft $cname Import"
            bucklist+=$(echo "$cname ")
            #terraform state list $ttft.$cname &> /dev/null
            #if [[ $? -ne 0 ]];then
            . ../../scripts/parallel_import3.sh $ttft $cname &
            #fi
            jc=$(jobs -r | wc -l | tr -d ' ')
            while [ $jc -gt $ncpu ]; do
                echo "Throttling - $jc Terraform imports in progress"
                sleep 10
                jc=$(jobs -r | wc -l | tr -d ' ')
            done
        else
            echo "Bucket $cname is not in region $theregion skipping ...."
            skipbucks+=(echo "$cname ")
        fi #in region

    fi # cname is not null
done   # for cname

jc=$(jobs -r | wc -l | tr -d ' ')
if [ $jc -gt 0 ]; then
    echo "Waiting for $jc Terraform imports"
    wait
    echo "Finished importing"
fi


for cname in ${bucklist[@]}; do
    cname=$(echo $cname | tr -d '"')
    #echo $cname

    #s3b=$(terraform state show -no-color $ttft.$cname 2> /dev/null)
    #echo "s3b==$s3b"
    echo "$ttft $cname tf files"
    #fn=$(printf "%s__%s.tf" $ttft $cname)
    fn=`printf "%s__b_%s.tf" $ttft $cname`
    if [ -f "$fn" ]; then echo "$fn exists already skipping" && continue; fi

    file=$(printf "%s-b_%s-1.txt" $ttft $cname)
    if [ ! -f "$file" ]; then echo "$file does not exist skipping" && continue; fi

    #fn=$(printf "%s__%s.tf" $ttft $cname)

    #flines=`echo "$s3b" | wc -l | awk '{ print $1 }'`
    flines=$(cat $file | wc -l | awk '{ print $1 }')
    #echo "$cname lines in file t1.txt= $flines"
    #echo "flines=$flines"
    lifec=0
    doacl2=0
    flc=0
    fd=0
    acl=0
    website=0
    keyid=""
    doacl=1
    doid=0
    dosse=0
    dover=0
    dopol=0
    dolog=0


    echo "--> $file $flines"
    echo $aws2tfmess >$fn


    while IFS= read line; do
        #echo "$s3b" | { while IFS= read -r line  # open { for varaible scope
        #    do
        skip=0
        # display $line or do something with $line
        t1=$(echo "$line")
        #echo "t1=$t1"
        t1t=$(echo "$t1" | tr -d ' ')
        #echo "t1t=$t1t"

        if [[ "$t1" == *"grant {"* ]]; then
            doacl=0
            doid=1
        fi

        if [[ "$t1" == *"server_side_encryption_configuration {"* ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            dosse=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi # server_side_encryption_configuration
        
        if [[ "$t1t" == "versioning{" ]]; then
            skip=1
            lbc=0
            rbc=0
            breq=0
            dover=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "versioning=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi

        if [[ "$t1t" == "logging{" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            dolog=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "logging=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi

        if [[ "$t1t" == "website{" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            website=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi # website

        if [[ ${t1t} == "grant{" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            doacl2=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi

        if [[ ${t1t} == "lifecycle_rule{" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            lifec=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi # lifecycle

        if [[ ${t1} == *"policy"*"jsonencode(" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            dopol=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"("* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *")"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done

        fi



        if [[ ${t1t} == "policy{" ]]; then
            #echo $t1
            skip=1
            lbc=0
            rbc=0
            breq=0
            dopol=1
            while [[ $breq -eq 0 ]]; do
                if [[ "${t1}" == *"{"* ]]; then lbc=$(expr $lbc + 1); fi
                if [[ "${t1}" == *"}"* ]]; then rbc=$(expr $rbc + 1); fi
                #echo "op=$lbc $rbc $t1"
                if [[ $rbc -eq $lbc ]]; then
                    breq=1
                else
                    read line
                    t1=$(echo "$line")
                fi
            done
        fi # policy

        if [[ ${t1} == *"="* ]]; then
            tt1=$(echo "$line" | cut -f1 -d'=' | tr -d ' ')
            tt2=$(echo "$line" | cut -f2- -d'=')

            if [[ ${tt1} == "arn" ]]; then skip=1; fi

            if [[ ${tt1} == "id" ]]; then skip=1; fi

            if [[ ${tt1} == "s3:"* ]]; then
                tt2=$(echo $tt2 | tr -d '"')
                tt1=$(echo $tt1 | tr -d '"')
                t1=$(printf "\"%s\" = \"%s\"" $tt1 $tt2)
            fi

            if [[ ${tt1} == "aws:"* ]]; then
                tt2=$(echo $tt2 | tr -d '"')
                tt1=$(echo $tt1 | tr -d '"')
                t1=$(printf "\"%s\" = \"%s\"" $tt1 $tt2)
            fi

            if [[ ${tt1} == "region" ]]; then skip=1; fi
            if [[ ${tt1} == "request_payer" ]]; then skip=1; fi
            if [[ ${tt1} == "kms_master_key_id" ]]; then

                keyid=$(echo $tt2 | tr -d '"')
                if [[ $keyid == *":"* ]]; then
                    keyid=$(echo $keyid | rev | cut -f1 -d'/' | rev)
                fi
                # quick check it exists

                $AWS kms describe-key --key-id $keyid &>/dev/null
                if [[ $? -eq 0 ]]; then
                    t1=$(printf "%s = aws_kms_key.k_%s.id" $tt1 $keyid)
                else
                    t1=$(printf "# COMMENT THIS KEY DOESN'T EXIST %s = aws_kms_key.k_%s.id" $tt1 $keyid)
                    keyid=""
                fi
            fi

            if [[ ${tt1} == "role_arn" ]]; then
                printf "provider = \"aws.regional\"\n" >>$fn
                skip=0
            fi
            #if [[ ${tt1} == "force_destroy" ]];then
            #skip=0
            #fd=1
            #fi
            if [[ ${tt1} == "acl" ]]; then
                if [[ "$doacl" == "1" ]]; then
                    skip=0
                    acl=1
                fi
            fi
#
#
            if [[ ${tt1} == "bucket_prefix" ]]; then skip=1; fi
#
#
            if [[ ${tt1} == "bucket_domain_name" ]]; then skip=1; fi
            if [[ ${tt1} == "bucket_regional_domain_name" ]]; then skip=1; fi
            if [[ ${tt1} == "allocated_capacity" ]]; then skip=1; fi
            if [[ ${tt1} == "hosted_zone_id" ]]; then skip=1; fi
            if [[ ${tt1} == "website_endpoint" ]]; then skip=1; fi
            if [[ ${tt1} == "website_domain" ]]; then skip=1; fi
        fi # *=*

        ((flc = flc + 1))
        if [[ $flc = $flines ]]; then
            if [[ $fd = 0 ]]; then
                echo "force_destroy=false" >>$fn
            fi
            if [[ $acl = 0 ]]; then
                if [[ "$doacl" == "1" ]]; then
                    #printf "acl = \"private\" \n" >>$fn
                    echo "depreciated acl = private"
                fi
            fi
        fi

        if [ "$skip" == "0" ]; then
            #echo $skip $t1 $ttft
            echo "$t1" >>$fn
        fi

        #done # while file
    done <"$file"


###########
    echo "Done $file loop"


    if [[ "$keyid" != "" ]]; then
        #echo "*** key for $keyid"
        ../../scripts/080-get-kms-key.sh $keyid
        #echo "*** key alias for $keyid"
        ../../scripts/081-get-kms-alias.sh $keyid
    fi

    #echo "Out: $cname $dopol $dover $doacl2 $dosse $lifec $website"
    if [[ $dolog -eq 1 ]]; then
        ../../scripts/get-aws_s3_bucket_logging.sh $cname &
    fi
    if [[ $dopol -eq 1 ]]; then
        ../../scripts/get-aws_s3_bucket_policy.sh $cname &
    fi
    if [[ $dover -eq 1 ]]; then
        echo "versioning job for $cname"
        ../../scripts/get-aws_s3_bucket_versioning.sh $cname &
    fi
    if [[ $doacl2 -eq 1 ]]; then
        #echo "acl job for $cname"
        ../../scripts/get-aws_s3_bucket_acl.sh $cname &
    fi
    if [[ $lifec -eq 1 ]]; then
        #echo "lifecycle job for $cname"
        ../../scripts/get-aws_s3_bucket_lifecycle_configuration.sh $cname &
    fi
    if [[ $dosse -eq 1 ]]; then
        #echo "sse job for $cname"
        ../../scripts/get-aws_s3_bucket_server_side_encryption_configuration.sh $cname &
    fi
    if [[ $website -eq 1 ]]; then
        #echo "website job for $cname"
        ../../scripts/get-aws_s3_bucket_website_configuration.sh $cname &
    fi

    ### here ??
    #../../scripts/get-s3-request-payer.sh $cname

    # Parallel job throttle
    jc=$(jobs -r | wc -l | tr -d ' ')
    while [ $jc -gt $ncpu ]; do
        echo "Throttling - $jc Terraform imports in progress"
        sleep 10
        jc=$(jobs -r | wc -l | tr -d ' ')
    done
    wait

    #}

done # cname
#echo "Done $cname"

jc=$(jobs -r | wc -l | tr -d ' ')
#echo "Pre state mv waiting for $jc jobs ....."
if [[ $jc -ne 0 ]]; then
    echo "Pre state move waiting for $jc jobs ....."
fi
wait

echo "state move ...."
sync
sleep 1
sync
../../scripts/parallel_statemv.sh aws_s3


echo "run cross checker"
../../scripts/cross-check-s3-all.sh
