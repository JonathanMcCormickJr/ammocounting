Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resource :signup, only: %i[new create], controller: "users"
  resource :settings, only: %i[show update]
  resources :statements, only: [] do
    collection do
      get :balance_sheet
      get :income_statement
      get :cash_flow
    end
  end
  resources :trades, only: :create
  resource :clock, only: :create

  resources :calibers, only: %i[index show], param: :slug

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
