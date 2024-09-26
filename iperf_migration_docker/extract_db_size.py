import pandas as pd

# Load the CSV file
file_path = 'results_new.csv'  # Update this if the path is different
df = pd.read_csv(file_path)

# Convert the 'database_size' column from KB to MB and round the values
df['database_size_mb'] = (df['database_size'] / 1024).round()

# Get the rounded values as a list
db_size_array = df['database_size_mb'].to_list()

# Print the list as a comma-separated string
print(",".join(map(str, db_size_array)))
