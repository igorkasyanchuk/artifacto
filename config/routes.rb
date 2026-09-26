Rails.application.routes.draw do
  if (content_host = Rails.configuration.x.content_host)
    pattern = Regexp.new('\A[a-z0-9]{%d}\.%s\z' % [ Artifact::SLUG_LENGTH, Regexp.escape(content_host) ])

    # Untrusted zone: one artifact per subdomain, nothing else answers here.
    constraints(host: pattern) do
      root to: "raw#show", as: :raw_artifact
      get "/robots.txt", to: "raw#robots", as: :raw_robots
      match "*path", to: "raw#not_found", via: :all
    end
  else
    # Single-origin mode. Only registered when there is no content zone to send
    # artifacts to — otherwise this would serve them on the app's own origin,
    # which is the exact thing the two-zone split exists to prevent.
    get "/raw/:slug", to: "raw#show", as: :raw_artifact
  end

  # Everything else is the app zone. Deliberately unconstrained by host so the
  # app works on whatever domain it is deployed under.
  devise_for :users, controllers: { sessions: "users/sessions" }

  root to: "pages#home"
  get "/robots.txt", to: "pages#robots", as: :app_robots
  get "/skill", to: "pages#skill", as: :skill
  get "/terms", to: "pages#terms", as: :terms
  get "/manifest", to: "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }

  get  "/a/:slug",        to: "artifacts#show",         as: :artifact
  post "/a/:slug/unlock", to: "artifacts#unlock",       as: :unlock_artifact
  post "/a/:slug/report", to: "abuse_reports#create",   as: :report_artifact

  namespace :admin do
    root to: "dashboard#show"
    resources :users, only: %i[index update]
    resources :artifacts, only: %i[index destroy], param: :slug do
      post :block, on: :member
    end
    resources :comments, only: %i[index destroy]
  end

  namespace :api do
    namespace :v1 do
      resources :artifacts, only: %i[create show update destroy], param: :slug do
        patch "extend", to: "artifacts#renew", on: :member
        resources :comments, only: %i[index create destroy]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
