import pandas as pd
import numpy as np
import os

np.random.seed(42) # reproducibable results
N = 1000 # number of samples to generate

def generate_data(n):
    rows = []
    for _ in range(n):
        exp = np.random.choice([0, 1, 2], p=[0.4, 0.4, 0.2])
        base_rpe = {0: 5.0, 1: 6.5, 2: 7.5}[exp]

        avg_rpe = float(np.clip(np.random.normal(base_rpe, 1.5), 1, 10))
        max_rpe = float(np.clip(avg_rpe + np.random.uniform(0, 2), 1, 10))
        duration = float(np.clip(np.random.normal(50, 15), 20, 120))
        ex_count = int(np.random.randint(3, 8))
        completion = float(np.clip(
            1.0 - (avg_rpe - 5) * 0.05 + np.random.normal(0, 0.1),
            0.3, 1.0
        ))
        exp_penalty = {0: 0.3, 1: 0.15, 2: 0.0}[exp]

        # Fatigue score formula
        fatigue = (
            0.35 * (avg_rpe / 10) +
            0.25 * (max_rpe / 10) +
            0.15 * (duration / 120) +
            0.15 * (1 - completion) +
            0.10 * exp_penalty
        )
        fatigue = float(np.clip(
            fatigue + np.random.normal(0, 0.05), 0.0, 1.0
        ))

        rows.append({
            'avg_rpe': round(avg_rpe, 1),
            'max_rpe': round(max_rpe, 1),
            'session_duration': round(duration, 0),
            'exercises_count': ex_count,
            'completion_rate': round(completion, 2),
            'experience_level': exp,
            'fatigue_score': round(fatigue, 3),
        })

    return pd.DataFrame(rows)

if __name__ == '__main__':
    df = generate_data(N)
    os.makedirs('ml', exist_ok=True)
    df.to_csv('ml/training_data.csv', index=False)
    print(f"Generated {N} samples")
    print(df.describe())
    print(f"\nFatigue distribution:")
    print(f"  Low  (<0.4):    {(df['fatigue_score'] < 0.4).sum()}")
    print(f"  Med  (0.4-0.7): {((df['fatigue_score'] >= 0.4) & (df['fatigue_score'] < 0.7)).sum()}")
    print(f"  High (>0.7):    {(df['fatigue_score'] >= 0.7).sum()}")