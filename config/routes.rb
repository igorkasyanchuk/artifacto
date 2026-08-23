Rails.application.routes.draw do
  content_host = Regexp.new('\A[a-z0-9]{%d}\.%s\z' % [ Artifact::SLUG_LENGTH, Regexp.escape(Rails.configuration.x.content_host) ])

  # Untrusted zone: one artifact per subdomain, nothing else answers here.
  constraints(host: content_host) do
    root to: "raw#show", as: :raw_artifact
    get "/robots.txt", to: "raw#robots", as: :raw_robots
    match "*path", to: "raw#not_found", via: :all
  end

  constraints(host: Rails.configuration.x.app_host) do
    root to: "pages#home"
    get "/robots.txt", to: "pages#robots", as: :app_robots

    get  "/a/:slug",        to: "artifacts#show",         as: :artifact
    post "/a/:slug/unlock", to: "artifacts#unlock",       as: :unlock_artifact
    post "/a/:slug/report", to: "abuse_reports#create",   as: :report_artifact

    namespace :admin do
      resources :artifacts, only: %i[index destroy], param: :slug do
        post :block, on: :member
      end
    end

    namespace :api do
      namespace :v1 do
        resources :artifacts, only: %i[create show update destroy], param: :slug do
          patch "extend", to: "artifacts#renew", on: :member
        end
      end
    end

    get "up" => "rails/health#show", as: :rails_health_check
  end
end
