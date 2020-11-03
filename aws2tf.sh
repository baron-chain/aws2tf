usage()
{ echo "Usage: $0 [-p <profile>(Default="default") ] [-c <yes|no(default)>] [-t <type>] [-r <region>] [-x <yes|no(default)>]" 1>&2; exit 1;
}
x="no"
p="default" # profile
f="no"
v="no"
r="no" # region
c="no" # combine mode

while getopts ":p:r:x:f:v:t:i:c:" o; do
    case "${o}" in
    #    a)
    #        s=${OPTARG}
    #    ;;
        i)
            i=${OPTARG}
        ;;
        t)
            t=${OPTARG}
        ;;
        r)
            r=${OPTARG}
        ;;
        x)
            x="yes"
        ;;
        p)
            p=${OPTARG}
        ;;
        f)
            f="yes"
        ;;
        v)
            v="yes"
        ;;
        c)
            c="yes"
        ;;
        
        *)
            usage
        ;;
    esac
done
shift $((OPTIND-1))

export aws2tfmess="# File generated by aws2tf see https://github.com/awsandy/aws2tf"

mysub=`aws sts get-caller-identity --profile $p | jq .Account | tr -d '"'`
if [ "$r" = "no" ]; then
echo "Region not specified - Getting region from aws cli ="
r=`aws configure get region`
echo $r
fi

if [ "$mysub" == "null" ]; then
    echo "Account is null exiting"
    exit
fi

mkdir -p generated/tf.$mysub/data

s=`echo $mysub`
cd generated/tf.$mysub

if [ "$f" = "no" ]; then
    if [ "$c" = "no" ]; then
        echo "Cleaning generated/tf.$mysub"
        rm -f resources*.txt *.sh
        rm -f processed.txt
        rm -f *.tf *.json
        rm -f terraform.*
        rm -rf .terraform   
    fi
else
    sort -u processed.txt > pt.txt
    cp pt.txt processed.txt
fi

rm -f import.log
#if [ "$f" = "no" ]; then
#    ../../scripts/resources.sh 2>&1 | tee -a import.log
#fi
export AWS="aws --profile $p --region $r --output json "
echo " "
echo "Account ID = ${s}"
echo "AWS Resource Group Filter = ${g}"
echo "Region = ${r}"
echo "AWS Profile = ${p}"
echo "Extract KMS Secrets to .tf files (insecure) = ${x}"
echo "Fast Forward = ${f}"
echo "Verify only = ${v}"
echo "Type filter = ${t}"
echo "Combine = ${c}"
echo "AWS command = ${AWS}"
echo " "


# cleanup from any previous runs
#rm -f terraform*.backup
#rm -f terraform.tfstate
#rm -f tf*.sh


# write the aws.tf file
printf "provider \"aws\" {\n" > aws.tf
printf " region = \"%s\" \n" $r >> aws.tf
printf " shared_credentials_file = \"~/.aws/credentials\" \n"  >> aws.tf
printf " version = \"= 3.8.0\" \n"  >> aws.tf
printf " profile = \"%s\" \n" $p >> aws.tf
printf "}\n" >> aws.tf

cat aws.tf

if [ "$t" == "no" ]; then 
t="*"
fi

pre="*"
if [ "$t" == "vpc" ]; then
pre="1*"
t="*"
if [ "$i" == "no" ]; then
    echo "VPC Id null exiting - specify with -i <vpc-id>"
    exit
fi
fi

if [ "$t" == "tgw" ]; then
pre="type"
t="transitgw"
if [ "$i" == "no" ]; then
    echo "TGW Id null exiting - specify with -i <tgw-id>"
    exiting
fi
fi


if [ "$t" == "ecs" ]; then
pre="3*"
if [ "$i" == "no" ]; then
    echo "Cluster Name null exiting - specify with -i <cluster-name>"
    exit
fi
fi


if [ "$t" == "eks" ]; then
pre="30*"
if [ "$i" == "no" ]; then
    echo "Cluster Name null exiting - specify with -i <cluster-name>"
    exit
fi
fi


pwd
if [ "$c" == "no" ]; then
    echo "terraform init"
    terraform init 2>&1 | tee -a import.log
fi

exclude="iam"

if [ "$t" == "iam" ]; then
pre="03*"
exclude="xxxxxxx"
fi

#############################################################################

date
lc=0
echo "t=$t"
echo "loop through providers"
pwd
for com in `ls ../../scripts/$pre-get-*$t*.sh | cut -d'/' -f4 | sort -g`; do    
    echo "$com"
    if [[ "$com" == *"${exclude}"* ]]; then
        echo "skipping $com"
    else
        docomm=". ../../scripts/$com $i"
        if [ "$f" = "no" ]; then
            eval $docomm 2>&1 | tee -a import.log
        else
            grep "$docomm" processed.txt
            if [ $? -eq 0 ]; then
                echo "skipping $docomm"
            else
                eval $docomm 2>&1 | tee -a import.log
            fi
        fi
        lc=`expr $lc + 1`

        file="import.log"
        while IFS= read -r line
        do
            if [[ "${line}" == *"Error"* ]];then
          
                if [[ "${line}" == *"Duplicate"* ]];then
                    echo "Ignoring $line"
                else
                    echo "Found Error: $line exiting .... (pass for now)"
                    
                fi
            fi

        done <"$file"

        echo "$docomm" >> processed.txt
        
    fi
    
done

#########################################################################


date

#if [ "$x" = "yes" ]; then
#    echo "Attempting to extract secrets"
#    ../../scripts/kms_secrets.sh
#fi

#rm -f terraform*.backup

echo "Terraform fmt ..."
terraform fmt
echo "Terraform validate ..."
terraform validate .


if [ "$v" = "yes" ]; then
    exit
fi

echo "Terraform Plan ..."
terraform plan .

echo "---------------------------------------------------------------------------"
echo "aws2tf output files are in generated/tf.$mysub"
echo "---------------------------------------------------------------------------"

if [ "$t" == "eks" ]; then
echo "aws eks update-kubeconfig --name $i"
fi