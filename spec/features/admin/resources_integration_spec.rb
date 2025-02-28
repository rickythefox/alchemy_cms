# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Resources", type: :system do
  let(:event)        { create(:event) }
  let(:second_event) { create(:event, name: "My second Event", entrance_fee: 12.32) }

  before { authorize_user(:as_admin) }

  describe "index view" do
    it "should have a button for creating a new resource items" do
      visit "/admin/events"
      expect(page).to have_selector("#toolbar div.button_with_label a.icon_button .icon.fa-plus")
    end

    it "should list existing items" do
      event
      second_event
      visit "/admin/events"
      expect(page).to have_content("My Event")
      expect(page).to have_content("something fancy")
      expect(page).to have_content("12.32")
    end

    it "should list existing resource-items nicely formatted" do
      event
      visit "/admin/events"
      expect(page).to have_selector("div#archive_all table.list")
    end

    describe "pagination" do
      before do
        create_list(:event, 15)
      end

      it "should limit the number of items per page based on alchemy's general configuration" do
        stub_alchemy_config(:items_per_page, 5)

        visit "/admin/events"
        expect(page).to have_selector("div#archive_all table.list tbody tr", count: 5)
        expect(page).to have_selector("div#archive_all .pagination .page", count: 3)
      end

      context "params containing per_page" do
        it "should limit the items per page based on the given value" do
          visit "/admin/events?per_page=3"
          expect(page).to have_selector("div#archive_all table.list tbody tr", count: 3)
          expect(page).to have_selector("div#archive_all .pagination .page", count: 5)
        end
      end
    end

    describe "filters" do
      let(:filter_count) { Event.alchemy_resource_filters.size }

      context "resource model has alchemy_resource_filters defined" do
        it "should show selectboxes for the filters" do
          visit "/admin/events"

          within "#library_sidebar #filter_bar" do
            expect(page).to have_selector("select", count: filter_count)
            expect(page).to have_selector("label", text: "Start")
            expect(page).to have_selector("label", text: "Location")
          end
        end

        context "selecting a filter option" do
          let(:location) { create(:location, name: "berlin") }

          before do
            create(:event, name: "today 1", starts_at: Time.current)
            create(:event, name: "today 2", starts_at: Time.current, location: location)
            create(:event, name: "yesterday", starts_at: Time.current - 1.day)
          end

          it "should filter the list to only show matching items", js: true do
            visit "/admin/events"

            within "div#archive_all table.list tbody" do
              expect(page).to have_selector("tr", count: 3)
              expect(page).to have_content("today 1")
              expect(page).to have_content("today 2")
              expect(page).to have_content("yesterday")
            end

            within "#library_sidebar #filter_bar" do
              select2("Starting today", from: "Start")
            end

            within "div#archive_all table.list tbody" do
              expect(page).to have_selector("tr", count: 2)
              expect(page).to have_content("today 1")
              expect(page).to have_content("today 2")
              expect(page).to_not have_content("yesterday")
            end
          end

          it "can combine multiple filters" do
            visit "/admin/events?filter[start]=starting_today&filter[by_location_name]=#{location.name}"

            within "div#archive_all table.list tbody" do
              expect(page).to have_selector("tr", count: 1)
              expect(page).to have_content("today 2")
              expect(page).to_not have_content("today 1")
            end
          end
        end
      end

      context "with no tagged items" do
        before do
          create(:event, tag_list: nil)
        end

        it "should not show the tag list" do
          visit "/admin/events"

          within "#library_sidebar" do
            expect(page).to_not have_selector(".tag-list")
          end
        end
      end

      context "with tagged items" do
        before do
          create_list(:event, 2, tag_list: ["remote"])
          create(:event, name: "onsite event", tag_list: ["onsite"])
        end

        it "should list all tags including the number of tagged items" do
          visit "/admin/events"

          within "#library_sidebar" do
            expect(page).to have_selector(".tag-list a", text: "remote (2)")
            expect(page).to have_selector(".tag-list a", text: "onsite (1)")
          end
        end

        context "selecting a tag from the list" do
          it "should filter the list to only show matching items" do
            visit "/admin/events"

            within "div#archive_all table.list tbody" do
              expect(page).to have_selector("tr", count: 3)
            end

            find("#library_sidebar .tag-list a", text: "onsite (1)").click

            within "div#archive_all table.list tbody" do
              expect(page).to have_selector("tr", count: 1)
              expect(page).to have_selector("td", text: "onsite event")
            end
          end
        end
      end
    end

    describe "date fields" do
      let(:yesterday) { Date.yesterday }
      let(:tomorrow) { Date.tomorrow }

      before do
        Booking.create(from: yesterday, until: tomorrow)
      end

      it "displays date values" do
        visit "/admin/bookings"
        expect(page).to have_content(yesterday)
        expect(page).to have_content(tomorrow)
      end
    end
  end

  describe "form for creating and updating items" do
    it "renders an input field according to the attribute's type" do
      visit "/admin/events/new"
      expect(page).to have_selector('input#event_name[type="text"]')
      expect(page).to have_selector('input#event_starts_at[data-datepicker-type="datetime"]')
      expect(page).to have_selector('input#event_ends_at[data-datepicker-type="datetime"]')
      expect(page).to have_selector("textarea#event_description")
      expect(page).to have_selector('input#event_published[type="checkbox"]')
      expect(page).to have_selector('input#event_lunch_starts_at[data-datepicker-type="time"]')
      expect(page).to have_selector('input#event_lunch_ends_at[data-datepicker-type="time"]')
    end

    it "should have a select box for associated models" do
      visit "/admin/events/new"
      within("form") do
        expect(page).to have_selector("select#event_location_id")
      end
    end

    it "should have a select box for enums values" do
      visit "/admin/events/new"

      within("form") do
        expect(page).to have_selector("select#event_event_type")
      end
    end

    describe "date fields" do
      it "have date picker" do
        visit "/admin/bookings/new"
        expect(page).to have_selector('input#booking_from[data-datepicker-type="date"]')
      end
    end
  end

  describe "create resource item" do
    context "when form filled with valid data" do
      let!(:location) { create(:location) }
      let(:start_date) { 1.week.from_now }

      before do
        visit "/admin/events/new"
        fill_in "event_name", with: "My second event"
        fill_in "event_starts_at", with: start_date
        select location.name, from: "Location"
        click_on "Save"
      end

      it "lists the new item" do
        expect(page).to have_content "My second event"
        expect(page).to have_content I18n.l(start_date, format: :'alchemy.default')
      end

      it "shows a success message" do
        expect(page).to have_content("Successfully created")
      end
    end

    context "when form filled with invalid data" do
      before do
        visit "/admin/events/new"
        fill_in "event_name", with: "" # invalid!
        click_on "Save"
      end

      it "shows the form again" do
        expect(page).to have_selector "form input#event_name"
      end

      it "lists invalid fields" do
        expect(page).to have_content("can't be blank")
      end

      it "should not display success notice" do
        expect(page).not_to have_content("successfully created")
      end
    end
  end

  describe "updating an item" do
    before do
      visit("/admin/events/#{event.id}/edit")
      fill_in "event_name", with: "New event name"
      click_on "Save"
    end

    it "shows the updated value" do
      expect(page).to have_content("New event name")
    end

    it "shows a success message" do
      expect(page).to have_content("Successfully updated")
    end
  end

  describe "destroying an item" do
    before do
      event
      second_event
      visit "/admin/events"
      within("tr", text: "My second Event") do
        click_on "Delete"
      end
    end

    it "shouldn't be on the list anymore" do
      expect(page).to have_content "My Event"
      expect(page).not_to have_content "My second Event"
    end

    it "should display success message" do
      expect(page).to have_content("Successfully removed")
    end
  end

  context "with event that acts_as_taggable" do
    it "shows an autocomplete tag list in the form" do
      visit "/admin/events/new"
      expect(page).to have_selector('input#event_tag_list[type="text"][data-autocomplete="/admin/tags/autocomplete"]')
    end

    context "with tagged events in the index view" do
      let!(:event)        { create(:event, name: "Casablanca", tag_list: "Matinee") }
      let!(:second_event) { create(:event, name: "Die Hard IX", tag_list: "Late Show") }

      before { visit "/admin/events" }

      it "shows the tag filter sidebar" do
        within "#library_sidebar" do
          expect(page).to have_content("Matinee")
          expect(page).to have_content("Late Show")
        end
      end

      it "filters the events when clicking a tag", aggregate_failures: true do
        click_link "Matinee"
        expect(page).to have_content("Casablanca")
        expect(page).to_not have_content("Die Hard IX")

        # Keep the tags when editing an event
        click_link "Edit"
        click_button "Save"
        expect(page).to have_content("Casablanca")
        expect(page).to_not have_content("Die Hard IX")
      end
    end
  end

  context "with event that has filters defined" do
    let!(:past_event) { create(:event, name: "Horse Expo", starts_at: Time.current - 100.years) }
    let!(:today_event) { create(:event, name: "Car Expo", starts_at: Time.current.at_noon) }
    let!(:future_event) { create(:event, name: "Hovercar Expo", starts_at: Time.current + 30.years) }

    it "lets the user filter by the defined scopes", aggregate_failures: true do
      visit "/admin/events"
      within "#library_sidebar" do
        expect(page).to have_content("Starting today")
        expect(page).to have_content("Future")
      end

      # Here we visit the pages manually, as we don't want to test the JS here.
      visit "/admin/events?filter[start]=starting_today"
      expect(page).to     have_content("Car Expo")
      expect(page).to_not have_content("Hovercar Expo")
      expect(page).to_not have_content("Horse Expo")

      visit "/admin/events?filter[start]=future"
      expect(page).to     have_content("Hovercar Expo")
      expect(page).to_not have_content("Car Expo")
      expect(page).to_not have_content("Horse Expo")

      # Keep the filter when editing an event
      click_link "Edit"
      click_button "Save"
      expect(page).to     have_content("Hovercar Expo")
      expect(page).to_not have_content("Car Expo")
      expect(page).to_not have_content("Horse Expo")
    end

    it "does not work with undefined scopes" do
      visit "/admin/events?filter[start]=undefined_scope"
      expect(page).to have_content("Car Expo")
      expect(page).to have_content("Hovercar Expo")
      expect(page).to have_content("Horse Expo")
    end

    context "full text search" do
      it "should respect filters" do
        visit "/admin/events?filter[start]=future"

        expect(page).to have_content("Hovercar Expo")
        expect(page).to_not have_content("Car Expo")
        expect(page).to_not have_content("Horse Expo")

        page.find(".search_input_field").set("Horse")
        page.find(".search_field button").click

        expect(page).to_not have_content("Hovercar Expo")
        expect(page).to_not have_content("Car Expo")
        expect(page).to_not have_content("Horse Expo")
      end
    end
  end
end
