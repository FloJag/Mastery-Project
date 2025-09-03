-- Step 1: Filtering
		-- Only take sessions in 2023 
    -- Select only engaged users (more than 7 sessions)
with sessions_2023 as (
  Select * 
  From sessions
  where session_start >='2023-01-05'
),

mehr_7_sessions as (
  Select user_id,
    		 count(session_id) as num_sessions
  From sessions_2023
  Group by user_id
  Having count(session_id) > 7
)

-- Step 2: Cleaning the Data
-- Step 3: Build session-based features 	 
, session_based as (
  SELECT *,
  	-- Clean Nights (fix negative values) 
  		case 
      when nights < 0 and return_time is not null then date(return_time) - date(check_in_time)
      when nights < 0 and return_time is null then nights * -1
      else date(check_out_time) - date(check_in_time)
    end as nights_cleaned,
		
  	-- calculate average page clicks per user  
    avg(page_clicks) over(partition by user_id) avg_page_clicks,
		
  	-- flag if trip was cancelled
    Max(CASE WHEN cancellation = true then 'cancelled'
             WHEN hotel_booked = false AND flight_booked = false THEN 'nothing booked' 
             ELSE 'not cancelled' END) OVER (Partition by trip_id) 
  					 as trip_was_cancelled,

    -- Clean flight_discount (fix missing values) 
    CASE WHEN flight_discount = true THEN 
  				COALESCE(flight_discount_amount,
              		(select avg(flight_discount_amount) FROM sessions where flight_discount = TRUE))
          ELSE NULL
          END	 
          AS new_flight_discount_amount,

    -- Clean flight_discount (fix missing values)
    CASE WHEN hotel_discount = true THEN 
  				COALESCE(hotel_discount_amount,
             			(select avg(hotel_discount_amount) FROM sessions where hotel_discount = TRUE))
          ELSE NULL
          END 
          AS new_hotel_discount_amount,

     -- Calculate Flight Distance      
     haversine_distance(
     	home_airport_lat,
      home_airport_lon,
      destination_airport_lat,
      destination_airport_lon)
      AS flight_distanz,

     -- Calculate price per booked seat
     base_fare_usd / seats        
      As price_per_person,

     -- Calculate Price per km
     base_fare_usd / haversine_distance(
      home_airport_lat,
      home_airport_lon,
      destination_airport_lat,
      destination_airport_lon) / seats
      AS price_per_person_per_km,

     -- Calculate Length of session
     extract(epoch from (session_end - session_start)) / 60
      AS length_of_session,

     -- Calculate Age 
     DATE_PART('YEAR', AGE(now(), birthdate))
      AS age,

     -- Calculate booking_type  
     CASE WHEN flight_booked = true AND hotel_booked = true THEN 'Flight & Hotel'
          WHEN flight_booked = true AND hotel_booked = false THEN 'Only Flight'
          WHEN flight_booked = false AND hotel_booked = true THEN 'Only Hotel'
          END
          AS booking_type,
  	 
     -- Calculate noting_booked
     CASE WHEN flight_booked = false AND hotel_booked = false THEN True 
  	 ELSE False
  	 END
  	 AS nothing_booked,

     -- Calculate day of week (5=Friday, 6=Saturday, 0=Sunday)         
     extract(dow from departure_time) 
  	 as departure_weekday,
  
     extract(dow from return_time) 
  	 as return_weekday

  FROM sessions_2023 
  JOin mehr_7_sessions 
    using(user_id)
  JOIN users 
    using(user_id)
  LEFT JOIN flights 
    using(trip_id)
  LEFT JOIN hotels 
    using(trip_id)
    )

-- Step 4: Create user-based view with features
, user_based_prep as (
  SELECT user_id,

     -- browsing behavior
     count(session_id) as total_sessions,
  
  	 ROUND(avg(page_clicks), 0) as avg_page_clicks,
  
     BOOL_AND(nothing_booked) 
  	 as no_bookings,

     -- travel behavior
     count(distinct trip_id) 
     as total_bookings,

     sum(case when hotel_booked AND cancellation = false then 1 else 0 end )
     as total_hotel_bookings,

     sum(case when flight_booked AND cancellation = false then 1 else 0 end) 
     as total_flights_bookings,
    
     sum(case when cancellation = false then seats end) 
     as total_seats,
  
  	 avg(base_fare_usd)
  	 as avg_price,
  
  	 avg(departure_weekday)
  	 as avg_departure_weekday,
  
  	 avg(return_weekday)
     as avg_return_weekday,
  
  	 avg(flight_distanz)::numeric
  	 as avg_flight_distanz,
  
  	 avg(price_per_person_per_km)::numeric
  	 as avg_price_per_p_km,
  	 
  	 avg(length_of_session)
  	 as avg_session_time,
  
  	 avg(checked_bags)
  	 as avg_bags_per_flight,
  
  	 avg(seats)
  	 as avg_seats_per_flight,
  
  	 avg(nights_cleaned)
  	 as avg_nights_per_flight,
  
  	 AVG(CASE WHEN booking_type = 'Nothing booked' THEN 1 ELSE 0 END )
  	 as ratio_nothing_booked,
  
     BOOL_OR(married) as is_married,
     BOOL_OR(has_children) as has_children,
     BOOL_OR(age > 67) as is_senior
  	 
 			
  FROM session_based
  GROUP BY user_id
 )

-- Step 5: Create final features for segmentation

, features_norm AS (
  SELECT user_id,
    
        CASE WHEN max(avg_seats_per_flight)> 2 THEN 1 ELSE 0
        END 
    	AS travelled_more_2_p,
    
    	CASE WHEN BOOL_OR(is_married) THEN 1 ELSE 0
    	END
    	AS is_married,
				 
        CASE WHEN BOOL_OR(has_children) THEN 1 ELSE 0
        END
        as has_children,
       
        CASE WHEN max(total_flights_bookings) >= 
    		 		(SELECT PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY total_flights_bookings) 
    		 		FROM user_based_prep) THEN 1    
        ELSE 0
        END 
        AS is_frequent_flyer,
         
        CASE WHEN max(avg_departure_weekday) IN(5,6) AND max(avg_return_weekday) = 0 THEN 1 
        ELSE 0
        END
        As is_weekender,
    
    	CASE WHEN max(avg_nights_per_flight) IN(1,2) THEN 1 ELSE 0
   		END 
    	AS short_trip,
              
        CASE WHEN max(avg_flight_distanz) > 3000 THEN 1 
        ELSE 0
        END
        AS is_long_distance_traveler,
         
     	CASE WHEN max(avg_price) >= 
    		 (SELECT PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY avg_price) 
    		 FROM user_based_prep) THEN 1
        ELSE 0
        END
        AS high_base_fare,
         
        CASE WHEN max(avg_price_per_p_km) >= 
    		 (SELECT PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY avg_price_per_p_km) 
    		 FROM user_based_prep) THEN 1
        ELSE 0
        END
        AS high_price_per_p_km,
         
        CASE WHEN BOOL_OR(is_senior) THEN 1
        ELSE 0
        END
        as is_old_age,
        
        CASE WHEN max(avg_page_clicks) < (SELECT PERCENTILE_DISC(0.20) WITHIN GROUP (ORDER BY avg_page_clicks) 
    		 FROM user_based_prep) THEN 1
        ELSE 0
        END
        AS is_low_page_clicks,
        
        CASE WHEN max(avg_session_time) < (SELECT PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY avg_session_time) 
    		 FROM user_based_prep) THEN 1
        ELSE 0
        END
        AS is_low_session_time,
              
        CASE WHEN max(avg_bags_per_flight) = 0 THEN 1 ELSE 0 end 
        as has_no_bags,
    
    	CASE WHEN max(avg_bags_per_flight) > 0 THEN 1 ELSE 0
    	END
    	AS has_bags,
         
        CASE WHEN max(avg_seats_per_flight) = 1 THEN 1 ELSE 0 end
        as traveled_alone,
         
        CASE WHEN BOOL_OR(avg_departure_weekday < avg_return_weekday
              AND avg_departure_weekday IN(1,2,3,4,5)
              AND avg_return_weekday IN(1,2,3,4,5)
              AND avg_nights_per_flight < 5 
             ) THEN 1
        ELSE 0
        END
        as trip_during_the_week,
         
        CASE WHEN BOOL_AND(no_bookings) = TRUE THEN 1
        ELSE 0
        END
        AS is_dreamer,
    
    		 CASE WHEN BOOL_AND(no_bookings) = FALSE THEN 1
        ELSE 0
        END
        AS has_bookings
                                     
	FROM user_based_prep
  GROUP BY 
  	user_id  
  ORDER BY user_id
  
  )
  
-- Step 6: Create Scores and set weights
  , scores as (
  SELECT 
    *,
    is_frequent_flyer 
    as score_is_frequent_flyer,
    is_long_distance_traveler 
    as score_is_long_distance_traveler,
    is_weekender * 0.5 + short_trip * 0.5 
    as score_is_weekender,
    is_dreamer 
    as score_is_dreamer,
    is_old_age * 0.8 + has_bookings * 0.2
    as score_is_senior,
    trip_during_the_week * 0.4 + traveled_alone * 0.2 + is_low_session_time * 0.1 + 
    has_no_bags * 0.2  + is_low_page_clicks * 0.1 
    as score_is_business,
    high_price_per_p_km * 0.5 + high_base_fare * 0.5
    as score_is_luxury,
    has_children * 0.1 + travelled_more_2_p * 0.6 + has_bags * 0.2 + is_married * 0.1
    as score_is_family
    	
  FROM features_norm
  )

-- Step 7: Create Logic to assign the users to a segment group
  , check_values as (
  SELECT 
      *, 
    case when score_is_dreamer = 1 
         		THEN 'Dreamer'
    		 when score_is_frequent_flyer = 1 
    				THEN 'Frequent Flyer' 
    		 when score_is_long_distance_traveler = 1 
         		THEN 'Long Distance Traveler'
         when score_is_business >= 
         	greatest(score_is_senior, score_is_weekender, score_is_luxury, score_is_family)
         		THEN 'Business'
         when score_is_luxury >= 
         	greatest(score_is_weekender, score_is_business, score_is_senior, score_is_family)
         		THEN 'Luxury'
         when score_is_family >= 
         	greatest(score_is_weekender, score_is_business, score_is_senior, score_is_luxury)
         		THEN 'Family'
         when score_is_weekender >= 
         	greatest(score_is_senior, score_is_business, score_is_luxury, score_is_family)
         		THEN 'Weekender'  
         when score_is_senior >= 
         	greatest(score_is_weekender, score_is_business, score_is_luxury, score_is_family)
         		THEN 'Senior'
         END 
         AS segment
   	
  FROM scores
  ),
  
-- Step 8: Add Perks to the segment groups
  
  perks as (
  SELECT *,
  		CASE WHEN segment = 'Dreamer' THEN 'Low-cost-trial'
      		 WHEN segment = 'Frequent Flyer' THEN 'Streak Rewards'
           WHEN segment = 'Long Distance Traveler' THEN '50% more Reward Points for Long-distance-Trips'
           WHEN segment = 'Business' THEN 'Instant-Rescheduling & Flexible Cancellation'
           WHEN segment = 'Luxury' THEN 'Exclusive Concierge Service'
           WHEN segment = 'Family' THEN '30% discount for groups of >= 3 with children'
           WHEN segment = 'Weekender' THEN 'exclusive Weekenddeals'
           WHEN segment = 'Senior' THEN 'Local Senior Support with free transportation'
           END
           AS Perks
  FROM check_values
  )
-- Show Distribution of Users in Segments
  SELECT segment, count(*) as num_users
  FROM check_values
  GROUP BY segment

 