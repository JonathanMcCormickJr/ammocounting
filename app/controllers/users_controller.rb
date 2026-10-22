class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_signup_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    result = Signup.call(user_params)
    if result.success?
      redirect_to sign_in(result.user)
    else
      @user = result.user
      render :new, status: :unprocessable_content
    end
  end

  private

  def user_params
    params.expect(user: %i[email_address password password_confirmation])
  end
end
