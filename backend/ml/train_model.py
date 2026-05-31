import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.preprocessing import StandardScaler
import joblib
import os

# Load data 
df = pd.read_csv(os.path.join(os.path.dirname(__file__), "training_data.csv"))

# Define features and label
#   avg_rpe = primary signal of perceived effort
#   max_rpe = captures single-exercise spikes (e.g. one brutal set)
#   session_duration = longer session = more accumulated fatigue
#   exercises_count  = volume proxy
#   completion_rate  = did they finish everything? low rate = gave up = high fatigue
#   experience_level = beginners fatigue faster at same absolute load

FEATURES = [
    "avg_rpe",
    "max_rpe",
    "session_duration",
    "exercises_count",
    "completion_rate",
    "experience_level",
]
LABEL = "fatigue_score"

X = df[FEATURES]
y = df[LABEL]

# Train/test split
# 80/20 Standard split. Enough data to train, enough to validate.
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# Scale features 
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Train model 
model = LinearRegression()
model.fit(X_train_scaled, y_train)

# Evaluate
y_pred = model.predict(X_test_scaled)
mae = mean_absolute_error(y_test, y_pred)
r2 = r2_score(y_test, y_pred)

print(f"\n=== Model Evaluation ===")
print(f"MAE  (Mean Absolute Error): {mae:.4f}")
print(f"R²   (Coefficient of Det.): {r2:.4f}")
print(f"\nInterpretation:")
print(f"  MAE {mae:.4f} means predictions are off by ~{mae:.2f} on a 0–1 fatigue scale")
print(f"  R²  {r2:.4f} means the model explains {r2*100:.1f}% of fatigue variance")

print(f"\n=== Feature Coefficients (after scaling) ===")
for feat, coef in zip(FEATURES, model.coef_):
    print(f"  {feat:20s}: {coef:+.4f}")

# Save model + scaler
model_dir = os.path.dirname(__file__)
joblib.dump(model, os.path.join(model_dir, "fatigue_model.pkl"))
joblib.dump(scaler, os.path.join(model_dir, "fatigue_scaler.pkl"))

print(f"\n✅ Model saved: ml/fatigue_model.pkl")
print(f"✅ Scaler saved: ml/fatigue_scaler.pkl")