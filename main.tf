terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 2.15.0"
    }
  }
}

locals {
  user1 = {
    username = "foo"
    password = "bar"
  }
}

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = "myroot"
}

# backend that allows user to authenticate
# using a combination of username and password
resource "vault_auth_backend" "userpass" {
  type = "userpass"
}

# a kv store where we can put secret things like credentials
resource "vault_mount" "credentials" {
  path = "my-credentials"
  type = "kv"

  options = {
    version = 2
  }
}

# some credentials for a qa databse
resource "vault_generic_secret" "qadb" {
  path = "${vault_mount.credentials.path}/team-qa/db"

  data_json = <<EOT
{
  "mysql_user": "bar",
  "mysql_passwd": "foo"
}
EOT
}

# some credentials for a dev databse
resource "vault_generic_secret" "devdb" {
  path = "${vault_mount.credentials.path}/team-dev/db"

  data_json = <<EOT
{
  "mysql_user": "eggs",
  "mysql_passwd": "spam"
}
EOT
}

# policy that allows reading any secrets in the path of team-qa
# from my-credentials kv store
resource "vault_policy" "qasecrets" {
  name = "qa-team"

  policy = <<EOT
path "${vault_mount.credentials.path}/*" {
  capabilities = [ "list" ]
}

path "${vault_mount.credentials.path}/data/team-qa/*" {
  capabilities = [ "read" ]
}
EOT
}

# group called qa that contains the entity `user1` and has
# a policy that allows any member to read the secrets from
# the path team-qa in our kv store
resource "vault_identity_group" "teamqa" {
  name = "team-qa"
  type = "internal"

  policies          = [vault_policy.qasecrets.name]
  member_entity_ids = [vault_identity_entity.user1.id]
}

# userpass credentials for user1
resource "vault_generic_endpoint" "user1" {
  path                 = "auth/${vault_auth_backend.userpass.path}/users/${local.user1.username}"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "password": "${local.user1.password}"
}
EOT
}

# entity that can be associated by vault with groups
resource "vault_identity_entity" "user1" {
  name = local.user1.username
}

# a mapping between user1 userpass to user1 entity
resource "vault_identity_entity_alias" "user1userpass" {
  name           = local.user1.username
  mount_accessor = vault_auth_backend.userpass.accessor
  canonical_id   = vault_identity_entity.user1.id
}
