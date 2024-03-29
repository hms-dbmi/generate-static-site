# generate-static-site

Creates a basic Jekyll repo, S3 bucket, and limited priv user which Travis will use to push updates

## Requirements

- Bash
- ERB
- [AWS CLI installed](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)
- [AWS CLI configured](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
- An AWS IAM account with sufficient privs
- A GitHub account
- [Travis CLI gem](https://docs.travis-ci.com/user/encryption-keys/#usage)

## Usage

Clone this repo and run `generate.sh`, and it will indicate what input is required.
New repos will be added to the `repos/` directory:
You can keep then there, or move them to a better location.
