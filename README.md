# Reward Program Analysis for Travel Tide

## Project Description
This project analyzes user assignments to the perks (rewards program) using SQL queries to identify key trends and insights.

## Project Goal ##
Define segment group of the users from Travel Tide and find perfectly fitted Perks that force them to join the reward programm.

## Project Summary
The project aimed to derive user-level insights from a session-based dataset and classify travelers into distinct customer segments. These segments serve as the foundation for assigning tailored perks that encourage users to join a reward program.

**Key Points and Insights:**
- Data preparation revealed anomalies (e.g., negative nights values), which were corrected to ensure consistency.
- Segmentation was based on travel and browsing behavior, using categorical thresholds (percentiles and binary features).
- The analysis highlighted a strong presence of business and family travelers, while also identifying smaller but relevant groups such as luxury travelers, frequent flyers, and dreamers.
- Outliers were intentionally retained, as they reflect meaningful traveler behavior (e.g., very high spending or long-distance travel).
- Example insight: Family travelers showed consistently higher group sizes, suggesting perks related to family-oriented services would be highly attractive.

## Database Connection
This project uses a hosted PostgreSQL instance.  

- Connection string should be stored in `config/` as:
  DATABASE_URL=postgres://<username>:<password>@<host>/<dbname>?sslmode=require

  Please replace with your own.

## Approach & Reasoning
The SQL analysis was designed in multiple steps:

1. **Create the table that fits the requirement for the analysis:**
   - Requirement 1: Only Data after January 4th, 2023 
   - Requirement 2 : Only Users with more than 7 sessions
    
    ***Filter sessions from 2023***
    - Created a CTE `sessions_2023` to only work with recent sessions starting after January 4th, 2023.  
      - This ensures the analysis focuses on the latest behavior.

    ***Identify active users***
    - CTE `mehr_7_sessions` selects only users with more than 7 sessions.  
      - Reasoning: infrequent users don’t provide reliable behavioral data and shouldn't be part of the analysis

2. **Cleaning the data**  
   - Calculated `nights_cleaned` (handling negative values) using return_time or times -1
      - Assumption: Nights are calculated with Check Out time -> Sometimes incorrect Entry in Check Out time
   - Handling missing in flight_dicount & hotel_discount by using the average of all discount values
      - Assumption: Amount entry was forgotten

3. **Add additional features & flags**
    - Added features like *price per person*, *price per km*, *length of session*, *booking_type*, *flight_distance* and *age*
      - Reasoning: these features are crucial for later segmentation.
    - Created a flag `trip_was_cancelled` that marks an entire trip as cancelled if any booking was cancelled. 
      - Reasoning: This prevents partial cancellations from being overlooked.

4. **Aggregated user-level view**  
   - Aggregate browsing travel behavior as well as specific demografical user information
   - Aggregated avgerages of seats, prices, bags, nights and more to build the basic features I need for the final ones.  
      - Purpose: to compare travel behavior across different demographic groups.

5. **Create one table with the final user features (which are needed for the segmentation)**
    - Aggregated all pre-build features to the final features for the segmentation groups
       i.e. is_frequent_flyer, is_weekender, is_long_distanz_traveler 

6. **Create scores and set weights**
    - After the process of building the final features I built the segments
    - Assign weights to the specific features to ensure each feature has his own importance within a group 
      (i.e. in my opinion the feature "traveled_more_2_persons" has more importance in the segment "Family" then the feature "is_married, so I gave it a higher weight)
    

7. **Create Logic to assign the users to a segment group**
    To assign each user to a unique segment, I developed a set of CASE WHEN statements that compare the calculated segment scores. The order of these statements is critical, as some users may achieve similar scores across multiple segments. In such cases, the order ensures that users are consistently assigned to the most representative segment.

    The sequence of assignment follows a clear rationale:

      - Single-criteria groups first: Segments that can only be defined by one distinct feature (e.g., age-based groups) are prioritized, as no alternative indicators exist to describe them.

      - High-spending groups next: Luxury and business travelers are considered before other groups, as their spending behavior sets them apart most clearly.

      - Family travelers: Families typically generate higher expenses due to longer stays and larger group sizes, which places them ahead of segments like weekenders or seniors.

    This structured prioritization ensures that users are not only assigned to one segment, but also to the one that best reflects their dominant behavior and characteristics.

8. **Define and add Perks to the segment groups**
    For each segment I defined one perfectly fitted perks which will force them to join the reward programm.
    - For example: For Seniors it's often hard to use online plattform. So I will offer them a easy booking-mode, where they have a simplified user-interface and a customer support especially for their purposes. 

## Segmentation ##
The goal of the segmentation was to group users based on their predominant travel behavior, derived from the engineered features.

For this project, I applied the weighted segmentation approach. Instead of working with continuous values, I defined clear thresholds and percentiles to transform behavioral indicators into binary variables (0/1). This ensures that each user is assigned to the segment that most strongly reflects their primary travel pattern, rather than with continouos variables, where the lower the better

**Why weighted segmentation with only 0/1 variables?**

Alternative methods such as clustering (e.g., k-means) or unsupervised machine learning models were considered. However, these approaches often result in segments that are mathematically valid but difficult to interpret from a business perspective. In contrast, weighted segmentation:

-  creates transparent and explainable rules (e.g., “users booking more than the 90th percentile of flights are frequent flyers”),
- ensures that every user can be assigned to exactly one segment,
- allows the segmentation to be directly translated into business logic, which is essential for marketing actions and reward program design.

By using this approach, I can guarantee that the final segments are both analytically robust and actionable for business strategy.

**NOTE**
I focused on averages of numerical features to capture users’ dominant behavior. This ensures that segments include only users who truly fit the profile (e.g., a traveler who sometimes flies alone and sometimes with family will not be labeled as a “typical” solo or family traveler, so they must be assigned to a different segment).

**Segments I choosed:**
  - Dreamer
  - Frequent Flyer
  - Long Distance Traveler
  - Business
  - Luxury
  - Family
  - Weekender
  - Senior

## Segment Features Overview

| **Segment**               | **Weighted Features)**                                                                 |
|---------------------------|-----------------------------------------------------------------------------------------------|
| **Dreamer**               | `is_dreamer = 1`                                                                              |
| **Frequent Flyer**        | `is_frequent_flyer = 1`                                                                       |
| **Long Distance Traveler**| `is_long_distance_traveler = 1`                                                               |
| **Business**              | `trip_during_the_week * 0.4 + traveled_alone * 0.2 + is_low_session_time * 0.1 + has_no_bags * 0.2 + is_low_page_clicks * 0.1` |
| **Luxury**                | `high_price_per_p_km * 0.5 + high_base_fare * 0.5`                                            |
| **Family**                | `has_children * 0.1 + travelled_more_2_p * 0.6 + has_bags * 0.2 + is_married * 0.1`           |
| **Weekender**             | `is_weekender * 0.5 + short_trip * 0.5`                                                       |
| **Senior**                | `is_old_age * 0.8 + has_bookings * 0.2`                                                       |
   


## Perks in Detail ##
**Dreamer:** 
Low-cost-trial (Test trip for low cost - up to 50% off)

**Frequent Flyer:** 
Streak Rewards (5 Flights within 6 Months -> Reward Points or Discounts)

**Long distance traveler:**
Extra Points for long-distance flights (extra Points to unlock speciell discounts)

**Business:** 
Instant-Rescheduling & Flexible Cancellation (without fees)

**Luxury:**
Exclusive Concierge Services (i.e. VIP pickup service)

**Family:**
30% Off for groups >= 3 with children

**Weekender:**
Weekend deals with one excursion for free 

**Seniors:**
Local Senior Support and Travlering for free -> One Local in the destination for extra support


## Outliers and Anomalies ##
During the data preparation phase, several anomalies were identified in the dataset (e.g., negative values for nights, or missing discount amounts although discount = TRUE). These issues were addressed through data cleaning, primarily by replacing invalid values with averages or imputing them with contextually appropriate values.

To further investigate potential anomalies, boxplots and histrograms were generated in Tableau to analyze the distribution of variables and detect outliers. After careful consideration, I decided not to remove the outliers from the dataset. The rationale behind this choice is that certain extreme values may reflect meaningful traveler behavior (e.g., luxury travelers with exceptionally high spending, or long-distance travelers with unusually high flight distances). Removing these observations could distort the data and limit the possibility of building relevant customer segments. 