#!/usr/bin/env bash
set -o errexit

die() { set +v; echo "$*" 1>&2 ; exit 1; }
b=$(tput bold)
n=$(tput sgr0)

[ "$#" = 1 ] || die 'Expects one argument, s3 bucket name (= site hostname).'
export BUCKET="$1" # Exported envvar used by ERB template
VALID_BUCKET_RE='^[a-z0-9-]+\.(org|com|io)$'
[[ "$BUCKET" =~ $VALID_BUCKET_RE ]] || die "'$BUCKET' does not match /$VALID_BUCKET_RE/."

DIR=`dirname $0`
CLEAN=`echo "$BUCKET" | sed -e 's/[^[:alnum:]]/-/g'`

aws_setup () {
  POLICY=`erb "$DIR/aws-template/policy.json.erb"`
  echo "${b}Filled policy template${n}"

  POLICY_NAME="$CLEAN-policy"
  POLICY_ARN=`aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY" \
    --description "Auto-generated policy for $BUCKET." \
    --query 'Policy.Arn' \
    --output text`
  echo "${b}Created policy${n} $POLICY_NAME ${b}with ARN${n} $POLICY_ARN"

  USER_NAME="$CLEAN-user"
  aws iam create-user \
    --user-name "$USER_NAME" > /dev/null
  echo "${b}Created user${n} $USER_NAME"

  aws iam attach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "$POLICY_ARN"
  echo "${b}Attached policy${n}"

  SECRET_ACCESS_KEY=`aws iam create-access-key \
    --user-name "$USER_NAME" \
    --query 'AccessKey.SecretAccessKey' \
    --output text`
  echo "${b}Secret access key${n} $SECRET_ACCESS_KEY"

  # Alternatively, we could get both the secret key and the ID at creation time.
  ACCESS_KEY_ID=`aws iam list-access-keys \
    --user-name "$USER_NAME" \
    --query 'AccessKeyMetadata[0].AccessKeyId' \
    --output text`
  echo "${b}Access key ID${n} $ACCESS_KEY_ID"

  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --acl public-read > /dev/null
  echo "${b}Created bucket${n} $BUCKET"

  # TODO: Copy Jekyll output
  aws s3 cp \
    --recursive \
    --acl public-read \
    "$DIR/site-template" "s3://$BUCKET"

  REGION=`aws configure get region`
  # Can't find an API that gives this to us?
  URL="http://$BUCKET.s3-website-$REGION.amazonaws.com"

  aws s3 website "s3://$BUCKET/" \
    --index-document index.html \
    --error-document error.html
  echo "${b}Set up static hosting${n} $URL"
}

repo_setup() {
  mkdir -p "repos/$BUCKET"
  for FILE in `find $DIR/repo-template`; do
    if [ -f "$FILE" ]; then
      BASE=`echo "$FILE" | sed -e 's/\.\/repo-template//'`
      if [[ $BASE == *.erb ]]; then
        TARGET=`echo "$BASE" | sed -e 's/\.erb$//'`
        erb "$FILE" > "repos/$BUCKET/$TARGET"
      else
        cp "$FILE" "repos/$BUCKET/$BASE"
      fi
    fi
  done
}

#aws_setup
repo_setup
