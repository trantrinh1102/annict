# frozen_string_literal: true

class RecordsController < ApplicationController
  permits :episode_id, :comment, :shared_twitter, :shared_facebook, :rating_state

  before_action :authenticate_user!, only: %i(create edit update destroy switch)
  before_action :load_user, only: %i(create show edit update destroy)
  before_action :load_record, only: %i(show edit update destroy)

  def show
    @work = @record.work
    @episode = @record.episode
    @comments = @record.comments.order(created_at: :desc)
    @comment = Comment.new
    @is_spoiler = user_signed_in? && current_user.hide_record_comment?(@episode)
  end

  def create(record)
    @episode = Episode.published.find(record[:episode_id])
    @work = @episode.work
    @record = @episode.records.new(record)
    ga_client.page_category = params[:page_category]

    service = NewRecordService.new(current_user, @record)
    service.page_category = params[:page_category]
    service.ga_client = ga_client
    service.via = "web"

    begin
      service.save!
      flash[:notice] = t("messages.records.created")
      redirect_to work_episode_path(@work, @episode)
    rescue
      params[:locale_en] = locale_en?
      params[:locale_ja] = locale_ja?
      service = RecordsListService.new(current_user, @episode, params)

      @all_records = service.all_records
      @all_comment_records = service.all_comment_records
      @friend_comment_records = service.friend_comment_records
      @my_records = service.my_records
      @selected_comment_records = service.selected_comment_records

      data = {
        recordsSortTypes: Setting.records_sort_type.options,
        currentRecordsSortType: current_user&.setting&.records_sort_type.presence || "created_at_desc"
      }
      gon.push(data)

      store_page_params(work: @work)

      @is_spoiler = current_user.hide_record_comment?(@episode)

      render "/episodes/show"
    end
  end

  def edit
    authorize @record, :edit?
    @work = @record.work
  end

  def update(record)
    authorize @record, :update?

    @record.modify_comment = true
    @record.detect_locale!(:comment)

    if @record.update_attributes(record)
      @record.update_share_record_status
      @record.share_to_sns
      path = record_path(@user.username, @record)
      redirect_to path, notice: t("messages.records.updated")
    else
      @work = @record.work
      render :edit
    end
  end

  def destroy
    authorize @record, :destroy?

    @record.destroy

    path = work_episode_path(@record.work, @record.episode)
    redirect_to path, notice: t("messages.records.deleted")
  end

  def switch(episode_id, to)
    episode = Episode.find(episode_id)

    return redirect_to work_episode_path(episode.work, episode) unless to.in?(Setting.display_option_record_list.values)

    current_user.setting.update_column(:display_option_record_list, to)
    redirect_to work_episode_path(episode.work, episode)
  end

  def redirect(provider, url_hash)
    case provider
    when "tw"
      record = Record.published.find_by!(twitter_url_hash: url_hash)

      log_messages = [
        "Twitterからのアクセス ",
        "remote_host: #{request.remote_host}, ",
        "remote_ip: #{request.remote_ip}, ",
        "remote_user: #{request.remote_user}"
      ]
      logger.info(log_messages.join)

      bots = TwitterBot.pluck(:name)
      no_bots = bots.map do |bot|
        request.user_agent.present? && !request.user_agent.include?(bot)
      end
      record.increment!(:twitter_click_count) if no_bots.all?

      redirect_to_user_record(record)
    when "fb"
      record = Record.published.find_by!(facebook_url_hash: url_hash)
      record.increment!(:facebook_click_count)

      redirect_to_user_record(record)
    else
      redirect_to root_path
    end
  end

  private

  def load_user
    @user = User.find_by!(username: params[:username])
  end

  def load_record
    @record = @user.records.find(params[:id])
  end

  def redirect_to_user_record(record)
    username = record.user.username

    redirect_to record_path(username, record)
  end
end
