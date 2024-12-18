import pandas as pd
import numpy as np

# Load the CSV file
file_path = 'results_new.csv'  # Update this if the path is different
df = pd.read_csv(file_path)

# Replace infinite values with NaN and then fill NaN values with 0
df['database_size'] = df['database_size'].replace([np.inf, -np.inf], np.nan).fillna(0)

# Convert the 'database_size' column from KB to MB, round the values, cast to integers
df['database_size_mb'] = (df['database_size'] / 1024).round().astype(int)

# Drop rows where 'database_size_mb' is 0
df = df[df['database_size_mb'] > 0]

# Get the unique values and sort them from smallest to largest
unique_db_sizes = sorted(df['database_size_mb'].unique())

# Print the sorted unique values as a comma-separated string
print(",".join(map(str, unique_db_sizes)))
