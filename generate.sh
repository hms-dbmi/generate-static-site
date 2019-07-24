#!/usr/bin/env bash
set -o errexit

die() { set +v; echo "$*" 1>&2 ; exit 1; }

[ "$#" = 1 ] || die 'Expects one argument, s3 bucket name (= site hostname).'

export HOST="$1"
[[ "$HOST" = *.org ]] || [[ "$HOST" = *.io ]] || die "'$HOST' does not look like a hostname."

CLEAN=`echo "$HOST" | sed -e 's/[^[:alnum:]]/-/g'`

DIR=`dirname $0`
POLICY=`erb "$DIR/aws-template/policy.json.erb"`
echo "Policy doc: $POLICY"

POLICY_NAME="$CLEAN-policy"
POLICY_ARN=`aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "$POLICY"  --description "Auto-generated policy for $HOST." --query 'Policy.Arn' --output text`
echo "Created $POLICY_NAME with ARN $POLICY_ARN"

USER_NAME="$CLEAN-user"
aws iam create-user \
  --user-name "$USER_NAME"
echo "Created $USER_NAME"

aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$POLICY_ARN"
echo  "Attached policy"
