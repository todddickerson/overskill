class Integrations::GithubInstallation < ApplicationRecord
  include Integrations::GithubInstallations::Base

  def process_webhook(webhook)
    raise "You should implement a `Integrations::GithubInstallation` model in your application that has `include Integrations::GithubInstallations::Base` and implements a `def process_webhook(webhook)` method."
  end
end
