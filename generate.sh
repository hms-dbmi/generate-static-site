#!/usr/bin/env bash
set -o errexit

die() { set +v; echo "$*" 1>&2 ; exit 1; }
b=$(tput bold)
r=$(tput rev)
n=$(tput sgr0)

[ "$#" = 2 ] || die 'Expects two arguments: github owner team/user, and s3 bucket name (= site hostname).'
export OWNER="$1"
export BUCKET="$2" # Exported envvar used by ERB template
VALID_BUCKET_RE='^[a-z0-9-]+\.(org|com|io)$'
[[ "$BUCKET" =~ $VALID_BUCKET_RE ]] || die "'$BUCKET' does not match /$VALID_BUCKET_RE/."

DIR=`dirname $0`
CLEAN=`echo "$BUCKET" | sed -e 's/[^[:alnum:]]/-/g'`
REPO="$OWNER/$CLEAN"

echo_title() {
  echo
  echo "${r}$1${n}"
  echo
}

preflight_checks() {
  echo_title 'Preflight checks ...'
  GH_API="https://api.github.com/repos/$REPO"
  curl --silent --fail "$GH_API" > /dev/null \
    || die "Please create '$REPO', but ${b}do not${n} initialize with a README: https://github.com/new"
  API_STATUS=`curl --silent --write-out '%{http_code}' "https://api.github.com/repos/$REPO/stats/contributors"`
  [[ "$API_STATUS" = '204' ]] \
    || die "'$REPO' is already initialized; This script requires a completely new, empty repo."

  aws iam get-user > /dev/null \
    || die "'get-user' failed: Check AWS credentials."
  aws s3api head-bucket --bucket "$BUCKET" 2> /dev/null \
    && die "'$BUCKET' should not already exist." \
    || true
  # Possible that it exists, but is owned by someone else.
}

aws_create_bucket() {
  echo_title 'Create bucket ...'
  # Create bucket first to make sure the name is free.
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --acl public-read > /dev/null

  aws s3api wait bucket-exists \
    --bucket "$BUCKET"

  echo "${b}Created bucket${n} $BUCKET"

  REGION=`aws configure get region`
  # Can't find an API that gives this to us?
  export URL="http://$BUCKET.s3-website-$REGION.amazonaws.com"

  aws s3 website "s3://$BUCKET/" \
    --index-document index.html \
    --error-document error.html
  echo "${b}Set up static hosting${n} $URL"
}

aws_iam_setup () {
  echo_title 'IAM setup ...'

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
  export ACCESS_KEY_ID=`aws iam list-access-keys \
    --user-name "$USER_NAME" \
    --query 'AccessKeyMetadata[0].AccessKeyId' \
    --output text`
  echo "${b}Access key ID${n} $ACCESS_KEY_ID"
}

init_repo() {
  echo_title 'Init repo ...'

  # Init the repo: it needs to exist before we can encrypt variables for travis
  git init "repos/$CLEAN"
  cd "repos/$CLEAN"
  echo "# $CLEAN" > README.md
  git add .
  git commit -m 'README'
  git remote add origin "https://github.com/$REPO.git"
  git push -u origin master
  cd -
}

fill_template() {
  echo_title 'Fill template ...'

  for FILE in `find $DIR/repo-template`; do
    if [ -f "$FILE" ]; then
      BASE=`echo "$FILE" | sed -e 's/\.\/repo-template//'`
      if [[ $BASE == *.erb ]]; then
        TARGET=`echo "$BASE" | sed -e 's/\.erb$//'`
        erb "$FILE" > "repos/$CLEAN/$TARGET"
      else
        cp "$FILE" "repos/$CLEAN/$BASE"
      fi
    fi
  done

  cd "repos/$CLEAN"
  git add .
  git commit -m 'Fill template'
  git push origin master
  cd -
}

encrypt_secret_access_key() {
  echo_title "Encrypt key..."

  echo "• Visit ${b}https://travis-ci.org/account/repositories${n} and click 'Sync account'."
  echo "• Find your new repo '${b}$REPO${n}' in the list and toggle it on."
  read -p '(When ready, hit return to continue...) '

  cd "repos/$CLEAN"
  travis encrypt SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" --add env.global
  git add .
  git commit -m 'Add encrypted key'
  git push origin master
  cd -
}

run_jekyll() {
  echo_title 'Jekyll dry run ...'
  # This should usually be done by travis...
  # but doing a trial run can uncover some problems.

  # TODO: Copy Jekyll output
  # aws s3 cp \
  #   --recursive \
  #   --acl public-read \
  #   "$DIR/site-template" "s3://$BUCKET"
}

preflight_checks
aws_create_bucket
aws_iam_setup
init_repo
fill_template
encrypt_secret_access_key
run_jekyll

echo_title 'Done'
echo "Repo initialized:"
echo "  Local:  {$b}repos/$CLEAN${n}"
echo "  GitHub: {$b}https://github.com/$REPO${n}"
echo "When you push changes to master, Travis will run Jekyll, push to S3,"
echo "and update $URL"
