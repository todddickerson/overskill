class Oauth::GithubAccount < ApplicationRecord
  include Oauth::GithubAccounts::Base
end
