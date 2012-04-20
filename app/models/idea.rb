class Idea < ActiveRecord::Base
  
  extend ActiveSupport::Memoizable
  
  include ActionView::Helpers::DateHelper

  acts_as_set_sub_instance :table_name=>"ideas"

  if Instance.current and Instance.current.is_suppress_empty_ideas?
    scope :published, :conditions => "ideas.status = 'published' and ideas.position > 0 and endorsements_count > 0"
  else
    scope :published, :conditions => "ideas.status = 'published'"
  end

  scope :published, :conditions => "ideas.status = 'published'"
  scope :unpublished, :conditions => "ideas.status not in ('published','abusive')"

  scope :not_deleted, :conditions => "ideas.status <> 'deleted'"

  scope :flagged, :conditions => "flags_count > 0"

  scope :alphabetical, :order => "ideas.name asc"

  scope :top_rank, :order => "ideas.score desc, ideas.position asc"

  scope :top_24hr, :conditions => "ideas.position_endorsed_24hr IS NOT NULL", :order => "ideas.position_endorsed_24hr asc"
  scope :top_7days, :conditions => "ideas.position_endorsed_7days IS NOT NULL", :order => "ideas.position_endorsed_7days asc"
  scope :top_30days, :conditions => "ideas.position_endorsed_30days IS NOT NULL", :order => "ideas.position_endorsed_30days asc"

  scope :not_top_rank, :conditions => "ideas.position > 25"
  scope :rising, :conditions => "ideas.trending_score > 0", :order => "ideas.trending_score desc"
  scope :falling, :conditions => "ideas.trending_score < 0", :order => "ideas.trending_score asc"
  scope :controversial, :conditions => "ideas.is_controversial = true", :order => "ideas.controversial_score desc"

  scope :rising_7days, :conditions => "ideas.position_7days_change > 0"
  scope :flat_7days, :conditions => "ideas.position_7days_change = 0"
  scope :falling_7days, :conditions => "ideas.position_7days_change < 0"
  scope :rising_30days, :conditions => "ideas.position_30days_change > 0"
  scope :flat_30days, :conditions => "ideas.position_30days_change = 0"
  scope :falling_30days, :conditions => "ideas.position_30days_change < 0"
  scope :rising_24hr, :conditions => "ideas.position_24hr_change > 0"
  scope :flat_24hr, :conditions => "ideas.position_24hr_change = 0"
  scope :falling_24hr, :conditions => "ideas.position_24hr_change < 0"
  
  scope :finished, :conditions => "ideas.official_status in (-2,-1,2)"
  
  scope :by_user_id, lambda{|user_id| {:conditions=>["user_id=?",user_id]}}
  scope :item_limit, lambda{|limit| {:limit=>limit}}
  scope :only_ids, :select => "ideas.id"
  
  scope :alphabetical, :order => "ideas.name asc"
  scope :newest, :order => "ideas.published_at desc, ideas.created_at desc"
  scope :tagged, :conditions => "(ideas.cached_issue_list is not null and ideas.cached_issue_list <> '')"
  scope :untagged, :conditions => "(ideas.cached_issue_list is null or ideas.cached_issue_list = '')", :order => "ideas.endorsements_count desc, ideas.created_at desc"

  scope :by_most_recent_status_change, :order => "ideas.status_changed_at desc"
  scope :by_random, :order => "rand()"

  scope :item_limit, lambda{|limit| {:limit=>limit}}  
  
  belongs_to :user
  belongs_to :sub_instance
  belongs_to :category
  
  has_many :relationships, :dependent => :destroy
  has_many :incoming_relationships, :foreign_key => :other_idea_id, :class_name => "Relationship", :dependent => :destroy
  
  has_many :endorsements, :dependent => :destroy
  has_many :endorsers, :through => :endorsements, :conditions => "endorsements.status in ('active','inactive')", :source => :user, :class_name => "User"
  has_many :up_endorsers, :through => :endorsements, :conditions => "endorsements.status in ('active','inactive') and endorsements.value=1", :source => :user, :class_name => "User"
  has_many :down_endorsers, :through => :endorsements, :conditions => "endorsements.status in ('active','inactive') and endorsements.value=-1", :source => :user, :class_name => "User"
    
  has_many :points, :conditions => "points.status in ('published','draft')"
  accepts_nested_attributes_for :points

  has_many :my_points, :conditions => "points.status in ('published','draft')", :class_name => "Point"
  accepts_nested_attributes_for :my_points
  
  has_many :incoming_points, :foreign_key => "other_idea_id", :class_name => "Point"
  has_many :published_points, :conditions => "status = 'published'", :class_name => "Point", :order => "points.helpful_count-points.unhelpful_count desc"
  has_many :points_with_deleted, :class_name => "Point", :dependent => :destroy

  has_many :rankings, :dependent => :destroy
  has_many :activities, :dependent => :destroy

  has_many :charts, :class_name => "IdeaChart", :dependent => :destroy
  has_many :ads, :dependent => :destroy
  has_many :notifications, :as => :notifiable, :dependent => :destroy
  
  has_many :changes, :conditions => "status <> 'deleted'", :order => "updated_at desc"
  has_many :approved_changes, :class_name => "Change", :conditions => "status = 'approved'", :order => "updated_at desc"
  has_many :sent_changes, :class_name => "Change", :conditions => "status = 'sent'", :order => "updated_at desc"
  has_many :declined_changes, :class_name => "Change", :conditions => "status = 'declined'", :order => "updated_at desc"
  has_many :changes_with_deleted, :class_name => "Change", :order => "updated_at desc", :dependent => :destroy
  has_many :idea_status_change_logs, dependent: :destroy

  attr_accessor :idea_type

  belongs_to :change # if there is currently a pending change, it will be attached
  
  acts_as_taggable_on :issues
  acts_as_list
  
  define_index do
    indexes name
    indexes category.name, :facet=>true, :as=>"category_name"
    has sub_instance_id, :as=>:sub_instance_id, :type => :integer
    where "ideas.status in ('published','inactive')"
  end  

  def category_name
    if category
      category.name
    else
      'No category'
    end
  end
    
  validates_length_of :name, :within => 5..60, :too_long => tr("has a maximum of 60 characters", "model/idea"),
                                               :too_short => tr("please enter more than 5 characters", "model/idea")

  validates_length_of :description, :within => 5..300, :too_long => tr("has a maximum of 300 characters", "model/idea"),
                                                       :too_short => tr("please enter more than 5 characters", "model/idea")

  validates_uniqueness_of :name, :if => Proc.new { |idea| idea.status == 'published' }
  validates :category_id, :presence => true

  after_create :on_published_entry

  include Workflow
  workflow_column :status
  workflow do
    state :published do
      event :delete, transitions_to: :deleted
      event :bury, transitions_to: :buried
      event :deactivate, transitions_to: :inactive
      event :abusive, transitions_to: :abusive
    end
    state :passive do
      event :publish, transitions_to: :published
      event :delete, transitions_to: :deleted
      event :bury, transitions_to: :buried
    end
    state :draft do
      event :publish, transitions_to: :published
      event :delete, transitions_to: :deleted
      event :bury, transitions_to: :buried
      event :deactivate, transitions_to: :inactive
    end
    state :deleted do
      event :bury, transitions_to: :buried
      event :undelete, transitions_to: :published, meta: { validates_presence_of: [:published_at] }
      event :undelete, transitions_to: :draft
    end
    state :buried do
      event :deactivate, transitions_to: :inactive
    end
    state :inactive do
      event :delete, transitions_to: :deleted
    end
    state :abusive
  end

  def to_param
    "#{id}-#{name.parameterize_full}"
  end  
  
  def content
    self.name
  end
  
  def endorse(user,request=nil,sub_instance=nil,referral=nil)
    return false if not user
    sub_instance = nil if sub_instance and sub_instance.id == 1 # don't log sub_instance if it's the default
    endorsement = self.endorsements.find_by_user_id(user.id)
    if not endorsement
      endorsement = Endorsement.new(:value => 1, :idea => self, :user => user, :sub_instance => sub_instance, :referral => referral)
      endorsement.ip_address = request.remote_ip if request
      endorsement.save
    elsif endorsement.is_down?
      endorsement.flip_up
      endorsement.save
    end
    if endorsement.is_replaced?
      endorsement.activate!
    end
    return endorsement
  end
  
  def oppose(user,request=nil,sub_instance=nil,referral=nil)
    return false if not user
    sub_instance = nil if sub_instance and sub_instance.id == 1 # don't log sub_instance if it's the default
    endorsement = self.endorsements.find_by_user_id(user.id)
    if not endorsement
      endorsement = Endorsement.new(:value => -1, :idea => self, :user => user, :sub_instance => sub_instance, :referral => referral)
      endorsement.ip_address = request.remote_ip if request
      endorsement.save
    elsif endorsement.is_up?
      endorsement.flip_down
      endorsement.save
    end
    if endorsement.is_replaced?
      endorsement.activate!
    end
    return endorsement
  end  
  
  def is_official_endorsed?
    official_value == 1
  end
  
  def is_official_opposed?
    official_value == -1
  end
  
  def is_rising?
    position_7days_change > 0
  end  

  def is_falling?
    position_7days_change < 0
  end
  
  def up_endorsements_count
    Endorsement.where(:idea_id=>self.id, :value=>1).count
  end
  
  def down_endorsements_count
    Endorsement.where(:idea_id=>self.id, :value=>-1).count
  end
  
  def is_controversial?
    return false unless down_endorsements_count > 0 and up_endorsements_count > 0
    (up_endorsements_count/down_endorsements_count) > 0.5 and (up_endorsements_count/down_endorsements_count) < 2
  end
  
  def is_buried?
    status == tr("delisted", "model/idea")
  end
  
  def is_top?
    return false if position == 0
    position < Endorsement.max_position
  end
  
  def is_new?
    return true if not self.attribute_present?("created_at")
    created_at > Time.now-(86400*7) or position_7days == 0    
  end

  def is_published?
    ['published','inactive'].include?(status)
  end
  alias :is_published :is_published?

  def is_finished?
    official_status > 1 or official_status < 0
  end
  
  def is_failed?
    official_status == -2
  end
  
  def is_successful?
    official_status == 2
  end
  
  def is_compromised?
    official_status == -1
  end
  
  def is_intheworks?
    official_status == 1
  end  
  
  def request=(request)
    if request
      self.ip_address = request.remote_ip
      self.user_agent = request.env['HTTP_USER_AGENT']
    else
      self.ip_address = "127.0.0.1"
      self.user_agent = "Import"
    end
  end
  
  def position_7days_change_percent
    position_7days_change.to_f/(position+position_7days_change).to_f
  end
  
  def position_24hr_change_percent
    position_24hr_change.to_f/(position+position_24hr_change).to_f
  end  
  
  def position_30days_change_percent
    position_30days_change.to_f/(position+position_30days_change).to_f
  end  
  
  def value_name 
    if is_failed?
      tr("Idea failed", "model/idea")
    elsif is_successful?
      tr("Idea succesful", "model/idea")
    elsif is_compromised?
      tr("Idea succesful with compromises", "model/idea")
    elsif is_intheworks?
      tr("Idea in the works", "model/idea")
    else
      tr("Idea has not been processed", "model/idea")
    end
  end
  
  def change_status!(change_status)
    if change_status == 0
      reactivate!
    elsif change_status == 2
      successful!
    elsif change_status == -2
      failed!
    elsif change_status == -1
      in_the_works!
    end
  end

  def reactivate!
    self.status_changed_at = Time.now
    self.official_status = 0
    self.status = 'published'
#    self.change = nil
    self.save(:validate => false)
#    deactivate_endorsements  
  end
  
  def failed!
    ActivityIdeaOfficialStatusFailed.create(:idea => self)
    self.status_changed_at = Time.now
    self.official_status = -2
    self.status = 'inactive'
#    self.change = nil
    self.save(:validate => false)
    #deactivate_endorsements
  end
  
  def successful!
    ActivityIdeaOfficialStatusSuccessful.create(:idea => self)
    self.status_changed_at = Time.now
    self.official_status = 2
    self.status = 'inactive'
#    self.change = nil    
    self.save(:validate => false)
    #deactivate_endorsements
  end  

  def in_the_works!
    ActivityIdeaOfficialStatusInTheWorks.create(:idea => self)
    self.status_changed_at = Time.now
    self.official_status = -1
    self.status = 'inactive'
#    self.change = nil
    deactivate_ads_and_refund
    self.save(:validate => false)
    #deactivate_endorsements
  end  
  
  def compromised!
    ActivityIdeaOfficialStatusCompromised.create(:idea => self)
    self.status_changed_at = Time.now
    self.official_status = -1
    self.status = 'inactive'
 #   self.change = nil    
    self.save(:validate => false)
    #deactivate_endorsements
  end

  def deactivate_ads_and_refund
    self.ads.active.each do |ad|
      ad.finish!
      user = ad.user
      refund = ad.cost - ad.spent
      refund = 1 if refund > 0 and refund < 1
      refund = refund.abs.to_i
      if refund
        user.increment!(:capital_count, refund)
        ActivityCapitalAdRefunded.create(:user => user, :idea => self, :capital => CapitalAdRefunded.create(:recipient => user, :amount => refund))
      end
    end
  end

  def deactivate_endorsements
    for e in endorsements.active
      e.finish!
    end    
  end

  def create_status_update(idea_status_change_log)
    return ActivityIdeaStatusUpdate.create(idea: self, idea_status_change_log: idea_status_change_log)
  end

  def reactivate!
    self.status = 'published'
    self.change = nil
    self.status_changed_at = Time.now
    self.official_status = 0
    self.save(:validate => false)
    for e in endorsements.active_and_inactive
      e.update_attribute(:status,'active')
      row = 0
      for ue in e.user.endorsements.active.by_position
        row += 1
        ue.update_attribute(:position,row) unless ue.position == row
        e.user.update_attribute(:top_endorsement_id,ue.id) if e.user.top_endorsement_id != ue.id and row == 1
      end      
    end
  end
  
  def intheworks!
    ActivityIdeaOfficialStatusInTheWorks.create(:idea => self, :user => user)
    self.update_attribute(:status_changed_at, Time.now)
    self.update_attribute(:official_status, 1)
  end  
  
  def official_status_name
    return tr("Failed", "status_messages") if official_status == -2
    return tr("In Progress", "status_messages") if official_status == -1
    return tr("Unknown", "status_messages") if official_status == 0
    return tr("Published", "status_messages") if official_status == 1
    return tr("Successful", "status_messages") if official_status == 2
  end
  
  def has_change?
    attribute_present?("change_id") and self.status != 'inactive' and change and not change.is_expired?
  end

  def has_tags?
    attribute_present?("cached_issue_list")
  end
  
  def replaced?
    attribute_present?("change_id") and self.status == 'inactive'
  end
  
  def movement_text
    s = ''
    if status == 'buried'
      return tr("delisted", "model/idea").capitalize
    elsif status == 'inactive'
      return tr("inactive", "model/idea").capitalize
    elsif created_at > Time.now-86400
      return tr("new", "model/idea").capitalize
    elsif position_24hr_change == 0 and position_7days_change == 0 and position_30days_change == 0
      return tr("no change", "model/idea").capitalize
    end
    s += '+' if position_24hr_change > 0
    s += '-' if position_24hr_change < 0    
    s += tr("no change", "model/idea") if position_24hr_change == 0
    s += position_24hr_change.abs.to_s unless position_24hr_change == 0
    s += ' today'
    s += ', +' if position_7days_change > 0
    s += ', -' if position_7days_change < 0    
    s += ', ' + tr("no change", "model/idea") if position_7days_change == 0
    s += position_7days_change.abs.to_s unless position_7days_change == 0
    s += ' this week'
    s += ', and +' if position_30days_change > 0
    s += ', and -' if position_30days_change < 0    
    s += ', and ' + tr("no change", "model/idea") if position_30days_change == 0
    s += position_30days_change.abs.to_s unless position_30days_change == 0
    s += ' this month'    
    s
  end
  
  def up_endorser_ids
    endorsements.active_and_inactive.endorsing.collect{|e|e.user_id.to_i}.uniq.compact
  end  
  def down_endorser_ids
    endorsements.active_and_inactive.opposing.collect{|e|e.user_id.to_i}.uniq.compact
  end
  def endorser_ids
    endorsements.active_and_inactive.collect{|e|e.user_id.to_i}.uniq.compact
  end
  def all_idea_ids_in_same_tags
    ts = Tagging.find(:all, :conditions => ["tag_id in (?) and taggable_type = 'Idea'",taggings.collect{|t|t.tag_id}.uniq.compact])
    return ts.collect{|t|t.taggable_id}.uniq.compact
  end
  
  def undecideds
    return [] unless has_tags? and endorsements_count > 2    
    User.find_by_sql("
    select distinct users.* 
    from users, endorsements
    where endorsements.user_id = users.id
    and endorsements.status = 'active'
    and endorsements.idea_id in (#{all_idea_ids_in_same_tags.join(',')})
    and endorsements.user_id not in (#{endorser_ids.join(',')})
    ")
  end
  memoize :up_endorser_ids, :down_endorser_ids, :endorser_ids, :all_idea_ids_in_same_tags, :undecideds
  
  def related(limit=10)
    Idea.find_by_sql(["SELECT ideas.*, count(*) as num_tags
    from taggings t1, taggings t2, ideas
    where 
    t1.taggable_type = 'Idea' and t1.taggable_id = ?
    and t1.tag_id = t2.tag_id
    and t2.taggable_type = 'Idea' and t2.taggable_id = ideas.id
    and t2.taggable_id <> ?
    and ideas.status = 'published'
    group by ideas.id
    order by num_tags desc, ideas.endorsements_count desc
    limit ?",id,id,limit])  
  end  
  
  def merge_into(p2_id,preserve=false,flip=0) #pass in the id of the idea to merge this one into.
    p2 = Idea.find(p2_id) # p2 is the idea that this one will be merged into
    for e in endorsements
      if not exists = p2.endorsements.find_by_user_id(e.user_id)
        e.idea_id = p2.id
        if flip == 1
          if e.value < 0
            e.value = 1 
          else
            e.value = -1
          end
        end   
        e.save(:validate => false)     
      end
    end
    p2.reload
    size = p2.endorsements.active_and_inactive.length
    up_size = p2.endorsements.active_and_inactive.endorsing.length
    down_size = p2.endorsements.active_and_inactive.opposing.length
    Idea.update_all("endorsements_count = #{size}, up_endorsements_count = #{up_size}, down_endorsements_count = #{down_size}", ["id = ?",p2.id])

    # look for the activities that should be removed entirely
    for a in Activity.find(:all, :conditions => ["idea_id = ? and type in ('ActivityIdeaDebut','ActivityIdeaNew','ActivityIdeaRenamed','ActivityIdeaFlag','ActivityIdeaFlagInappropriate','ActivityIdeaOfficialStatusCompromised','ActivityIdeaOfficialStatusFailed','ActivityIdeaOfficialStatusIntheworks','ActivityIdeaOfficialStatusSuccessful','ActivityIdeaRising1','ActivityIssueIdea1','ActivityIssueIdeaControversial1','ActivityIssueIdeaOfficial1','ActivityIssueIdeaRising1')",self.id])
      a.destroy
    end    
    #loop through the rest of the activities and move them over
    for a in activities
      if flip == 1
        for c in a.comments
          if c.is_opposer?
            c.is_opposer = false
            c.is_endorser = true
            c.save(:validate => false)
          elsif c.is_endorser?
            c.is_opposer = true
            c.is_endorser = false
            c.save(:validate => false)            
          end
        end
        if a.class == ActivityEndorsementNew
          a.update_attribute(:type,'ActivityOppositionNew')
        elsif a.class == ActivityOppositionNew
          a.update_attribute(:type,'ActivityEndorsementNew')
        elsif a.class == ActivityEndorsementDelete
          a.update_attribute(:type,'ActivityOppositionDelete')
        elsif a.class == ActivityOppositionDelete
          a.update_attribute(:type,'ActivityEndorsementDelete')
        elsif a.class == ActivityEndorsementReplaced
          a.update_attribute(:type,'ActivityOppositionReplaced')
        elsif a.class == ActivityOppositionReplaced 
          a.update_attribute(:type,'ActivityEndorsementReplaced')
        elsif a.class == ActivityEndorsementReplacedImplicit
          a.update_attribute(:type,'ActivityOppositionReplacedImplicit')
        elsif a.class == ActivityOppositionReplacedImplicit
          a.update_attribute(:type,'ActivityEndorsementReplacedImplicit')
        elsif a.class == ActivityEndorsementFlipped
          a.update_attribute(:type,'ActivityOppositionFlipped')
        elsif a.class == ActivityOppositionFlipped
          a.update_attribute(:type,'ActivityEndorsementFlipped')
        elsif a.class == ActivityEndorsementFlippedImplicit
          a.update_attribute(:type,'ActivityOppositionFlippedImplicit')
        elsif a.class == ActivityOppositionFlippedImplicit
          a.update_attribute(:type,'ActivityEndorsementFlippedImplicit')
        end
      end
      if preserve and (a.class.to_s[0..26] == 'ActivityIdeaAcquisition' or a.class.to_s[0..25] == 'ActivityCapitalAcquisition')
      else
        a.update_attribute(:idea_id,p2.id)
      end      
    end
    for a in ads
      a.update_attribute(:idea_id,p2.id)
    end    
    for point in points_with_deleted
      point.idea = p2
      if flip == 1
        if point.value > 0
          point.value = -1
        elsif point.value < 0
          point.value = 1
        end 
        # need to flip the helpful/unhelpful counts
        helpful = point.endorser_helpful_count
        unhelpful = point.endorser_unhelpful_count
        point.endorser_helpful_count = point.opposer_helpful_count
        point.endorser_unhelpful_count = point.opposer_unhelpful_count
        point.opposer_helpful_count = helpful
        point.opposer_unhelpful_count = unhelpful        
      end      
      point.save(:validate => false)      
    end
    for point in incoming_points
      if flip == 1
        point.other_idea = nil
      elsif point.other_idea == p2
        point.other_idea = nil
      else
        point.other_idea = p2
      end
      point.save(:validate => false)
    end
    if not preserve # set preserve to true if you want to leave the Change and the original idea in tact, otherwise they will be deleted
      for c in changes_with_deleted
        c.destroy
      end
    end
    # find any issues they may be the top prioritiy for, and remove
    for tag in Tag.find(:all, :conditions => ["top_idea_id = ?",self.id])
      tag.update_attribute(:top_idea_id,nil)
    end
    # zap all old rankings for this idea
    Ranking.connection.execute("delete from rankings where idea_id = #{self.id.to_s}")
    self.reload
    self.destroy if not preserve
    return p2
  end
  
  def flip_into(p2_id,preserve=false) #pass in the id of the idea to flip this one into.  it'll turn up endorsements into down endorsements and vice versa
    merge_into(p2_id,1)
  end  
  
  def show_url
    if self.sub_instance_id
      Instance.current.homepage_url(self.sub_instance) + 'ideas/' + to_param
    else
      Instance.current.homepage_url + 'ideas/' + to_param
    end
  end
  
  def show_discussion_url
    show_url + '/discussions'
  end

  def show_top_points_url
    show_url + '/top_points'
  end

  def show_endorsers_url
    show_url + '/endorsers'
  end

  def show_opposers_url
    show_url + '/opposers'
  end
  
  # this uses http://is.gd
  def create_short_url
    self.short_url = open('http://is.gd/create.php?longurl=' + show_url, "UserAgent" => "Ruby-ShortLinkCreator").read[/http:\/\/is\.gd\/\w+(?=" onselect)/]
  end

  def latest_idea_process_at
    latest_idea_process_txt = Rails.cache.read("latest_idea_process_at_#{self.id}")
    unless latest_idea_process_txt
      idea_process = IdeaProcess.find_by_idea_id(self, :order=>"created_at DESC, stage_sequence_number DESC")
      if idea_process
        time = idea_process.last_changed_at
      else
        time = Time.now-5.years
      end
      if idea_process.stage_sequence_number == 1 and idea_process.process_discussions.count == 0
        stage_txt = "#{tr("Waiting for discussion","althingi_texts")}"
      else
        stage_txt = "#{idea_process.stage_sequence_number}. #{tr("Discussion stage","althingi_texts")}"
      end
      latest_idea_process_txt = "#{stage_txt}, #{distance_of_time_in_words_to_now(time)}"
      Rails.cache.write("latest_idea_process_at_#{self.id}", latest_idea_process_txt, :expires_in => 30.minutes)
    end
    latest_idea_process_txt.html_safe if latest_idea_process_txt
  end

  def on_abusive_entry(new_state, event)
    self.user.do_abusive!(notifications)
    self.update_attribute(:flags_count, 0)
  end

  def flag_by_user(user)
    self.increment!(:flags_count)
    for r in User.active.admins
      notifications << NotificationIdeaFlagged.new(:sender => user, :recipient => r)
    end
  end  

  def on_published_entry(new_state = nil, event = nil)
    self.published_at = Time.now
    save(:validate => false) if persisted?
    ActivityIdeaNew.create(:user => user, :idea => self)
  end
  
  def on_deleted_entry(new_state, event)
    activities.each do |a|
      a.delete!
    end
    endorsements.each do |e|
      e.destroy
    end
    self.deleted_at = Time.now
    save(:validate => false)
  end
  
  def on_delete_entry(new_state, event)
    self.deleted_at = nil
    save(:validate => false)
  end  
  
  def on_buried_entry(new_state, event)
    # should probably send an email notification to the person who submitted it
    # but not doing anything for now.
  end
end