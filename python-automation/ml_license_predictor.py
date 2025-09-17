"""
Machine Learning License Prediction Model
Predicts future Adobe license usage based on historical data
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib
import json
import logging
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LicensePredictor:
    """ML model for predicting Adobe license usage"""

    def __init__(self, model_type: str = 'random_forest'):
        """
        Initialize the license predictor

        Args:
            model_type: Type of model to use ('linear' or 'random_forest')
        """
        self.model_type = model_type
        self.model = None
        self.is_trained = False
        self.feature_columns = []
        self.metrics = {}

        # Initialize model based on type
        if model_type == 'linear':
            self.model = LinearRegression()
        else:
            self.model = RandomForestRegressor(
                n_estimators=100,
                max_depth=10,
                random_state=42,
                n_jobs=-1
            )

    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features from raw license usage data

        Args:
            df: DataFrame with columns [date, product, department, users_count, licenses_used]

        Returns:
            DataFrame with engineered features
        """
        # Ensure date column is datetime
        df['date'] = pd.to_datetime(df['date'])

        # Extract time-based features
        df['year'] = df['date'].dt.year
        df['month'] = df['date'].dt.month
        df['quarter'] = df['date'].dt.quarter
        df['day_of_week'] = df['date'].dt.dayofweek
        df['week_of_year'] = df['date'].dt.isocalendar().week
        df['is_month_end'] = df['date'].dt.is_month_end.astype(int)
        df['is_quarter_end'] = df['date'].dt.is_quarter_end.astype(int)

        # Create lag features (previous usage patterns)
        for lag in [1, 7, 30]:
            df[f'licenses_lag_{lag}'] = df.groupby(['product', 'department'])['licenses_used'].shift(lag)

        # Rolling statistics
        for window in [7, 14, 30]:
            df[f'licenses_rolling_mean_{window}'] = df.groupby(['product', 'department'])['licenses_used'].transform(
                lambda x: x.rolling(window, min_periods=1).mean()
            )
            df[f'licenses_rolling_std_{window}'] = df.groupby(['product', 'department'])['licenses_used'].transform(
                lambda x: x.rolling(window, min_periods=1).std()
            )

        # Growth rate
        df['license_growth_rate'] = df.groupby(['product', 'department'])['licenses_used'].pct_change()

        # Department and product encoding
        df['department_encoded'] = pd.Categorical(df['department']).codes
        df['product_encoded'] = pd.Categorical(df['product']).codes

        # User-to-license ratio
        df['user_license_ratio'] = df['users_count'] / (df['licenses_used'] + 1)

        # Seasonal indicators
        df['is_summer'] = df['month'].isin([6, 7, 8]).astype(int)
        df['is_year_end'] = df['month'].isin([11, 12]).astype(int)

        # Fill NaN values
        df = df.fillna(0)

        return df

    def train(self,
              df: pd.DataFrame,
              target_column: str = 'licenses_used',
              test_size: float = 0.2) -> Dict:
        """
        Train the ML model

        Args:
            df: Training data
            target_column: Column to predict
            test_size: Proportion of data to use for testing

        Returns:
            Dictionary with training metrics
        """
        logger.info(f"Training {self.model_type} model...")

        # Prepare features
        df_features = self.prepare_features(df.copy())

        # Select feature columns
        feature_cols = [
            'year', 'month', 'quarter', 'day_of_week', 'week_of_year',
            'is_month_end', 'is_quarter_end', 'department_encoded', 'product_encoded',
            'users_count', 'user_license_ratio', 'is_summer', 'is_year_end',
            'licenses_lag_1', 'licenses_lag_7', 'licenses_lag_30',
            'licenses_rolling_mean_7', 'licenses_rolling_mean_14', 'licenses_rolling_mean_30',
            'licenses_rolling_std_7', 'licenses_rolling_std_14', 'licenses_rolling_std_30',
            'license_growth_rate'
        ]

        # Remove any columns that don't exist
        self.feature_columns = [col for col in feature_cols if col in df_features.columns]

        # Prepare X and y
        X = df_features[self.feature_columns]
        y = df_features[target_column]

        # Remove rows with NaN in target
        mask = ~y.isna()
        X = X[mask]
        y = y[mask]

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )

        # Train model
        self.model.fit(X_train, y_train)
        self.is_trained = True

        # Make predictions
        y_pred_train = self.model.predict(X_train)
        y_pred_test = self.model.predict(X_test)

        # Calculate metrics
        self.metrics = {
            'train_mae': mean_absolute_error(y_train, y_pred_train),
            'train_rmse': np.sqrt(mean_squared_error(y_train, y_pred_train)),
            'train_r2': r2_score(y_train, y_pred_train),
            'test_mae': mean_absolute_error(y_test, y_pred_test),
            'test_rmse': np.sqrt(mean_squared_error(y_test, y_pred_test)),
            'test_r2': r2_score(y_test, y_pred_test),
            'feature_importance': self.get_feature_importance()
        }

        logger.info(f"Model trained successfully. Test R2: {self.metrics['test_r2']:.3f}")

        return self.metrics

    def predict(self, df: pd.DataFrame) -> np.ndarray:
        """
        Make predictions on new data

        Args:
            df: DataFrame with same structure as training data

        Returns:
            Array of predictions
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before making predictions")

        # Prepare features
        df_features = self.prepare_features(df.copy())

        # Select same features used in training
        X = df_features[self.feature_columns]

        # Make predictions
        predictions = self.model.predict(X)

        # Ensure non-negative predictions
        predictions = np.maximum(predictions, 0)

        return predictions

    def predict_future(self,
                      historical_df: pd.DataFrame,
                      days_ahead: int = 30,
                      product: str = None,
                      department: str = None) -> pd.DataFrame:
        """
        Predict future license usage

        Args:
            historical_df: Historical usage data
            days_ahead: Number of days to predict
            product: Specific product to predict (None for all)
            department: Specific department to predict (None for all)

        Returns:
            DataFrame with predictions
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before making predictions")

        # Filter if specific product/department requested
        df = historical_df.copy()
        if product:
            df = df[df['product'] == product]
        if department:
            df = df[df['department'] == department]

        # Get unique combinations
        combinations = df[['product', 'department', 'users_count']].drop_duplicates()

        # Generate future dates
        last_date = pd.to_datetime(df['date']).max()
        future_dates = pd.date_range(
            start=last_date + timedelta(days=1),
            periods=days_ahead,
            freq='D'
        )

        # Create future DataFrame
        future_dfs = []
        for _, row in combinations.iterrows():
            future_data = pd.DataFrame({
                'date': future_dates,
                'product': row['product'],
                'department': row['department'],
                'users_count': row['users_count'],
                'licenses_used': 0  # Placeholder
            })

            # Add historical context for lag features
            historical_context = df[
                (df['product'] == row['product']) &
                (df['department'] == row['department'])
            ].tail(30)

            combined_df = pd.concat([historical_context, future_data], ignore_index=True)

            # Prepare features
            combined_features = self.prepare_features(combined_df)

            # Get only future rows for prediction
            future_features = combined_features.iloc[-days_ahead:]

            # Make predictions
            X_future = future_features[self.feature_columns]
            predictions = self.model.predict(X_future)

            # Create result DataFrame
            result = pd.DataFrame({
                'date': future_dates,
                'product': row['product'],
                'department': row['department'],
                'predicted_licenses': np.round(predictions).astype(int),
                'confidence_lower': np.maximum(0, predictions - predictions.std()),
                'confidence_upper': predictions + predictions.std()
            })

            future_dfs.append(result)

        # Combine all predictions
        all_predictions = pd.concat(future_dfs, ignore_index=True)

        return all_predictions

    def get_feature_importance(self) -> Dict[str, float]:
        """
        Get feature importance from trained model

        Returns:
            Dictionary of feature names and importance scores
        """
        if not self.is_trained:
            return {}

        if self.model_type == 'random_forest':
            importance = self.model.feature_importances_
            return {
                feature: float(importance[i])
                for i, feature in enumerate(self.feature_columns)
            }
        else:
            # For linear regression, use coefficients as importance
            coefficients = np.abs(self.model.coef_)
            return {
                feature: float(coefficients[i])
                for i, feature in enumerate(self.feature_columns)
            }

    def optimize_licenses(self,
                         predictions_df: pd.DataFrame,
                         buffer_percentage: float = 0.1) -> Dict:
        """
        Optimize license allocation based on predictions

        Args:
            predictions_df: DataFrame with predictions
            buffer_percentage: Safety buffer as percentage

        Returns:
            Dictionary with optimization recommendations
        """
        recommendations = {}

        # Group by product
        for product in predictions_df['product'].unique():
            product_data = predictions_df[predictions_df['product'] == product]

            # Calculate recommended licenses
            max_predicted = product_data['predicted_licenses'].max()
            avg_predicted = product_data['predicted_licenses'].mean()

            # Add buffer
            recommended = int(max_predicted * (1 + buffer_percentage))

            recommendations[product] = {
                'current_allocation': None,  # Would need current data
                'recommended_allocation': recommended,
                'max_predicted_usage': int(max_predicted),
                'avg_predicted_usage': int(avg_predicted),
                'buffer_applied': f"{buffer_percentage * 100:.0f}%",
                'departments': product_data['department'].unique().tolist()
            }

        return recommendations

    def save_model(self, filepath: str):
        """Save trained model to disk"""
        if not self.is_trained:
            raise ValueError("Model must be trained before saving")

        model_data = {
            'model': self.model,
            'model_type': self.model_type,
            'feature_columns': self.feature_columns,
            'metrics': self.metrics
        }

        joblib.dump(model_data, filepath)
        logger.info(f"Model saved to {filepath}")

    def load_model(self, filepath: str):
        """Load trained model from disk"""
        model_data = joblib.load(filepath)

        self.model = model_data['model']
        self.model_type = model_data['model_type']
        self.feature_columns = model_data['feature_columns']
        self.metrics = model_data['metrics']
        self.is_trained = True

        logger.info(f"Model loaded from {filepath}")


def generate_sample_data(days: int = 365) -> pd.DataFrame:
    """Generate sample historical data for testing"""
    np.random.seed(42)

    products = ['Creative Cloud', 'Acrobat Pro', 'Photoshop', 'Illustrator']
    departments = ['Marketing', 'Design', 'Engineering', 'Sales']

    data = []
    start_date = datetime.now() - timedelta(days=days)

    for day in range(days):
        current_date = start_date + timedelta(days=day)

        for product in products:
            for department in departments:
                # Simulate usage patterns
                base_usage = np.random.randint(10, 50)

                # Add seasonal variation
                seasonal_factor = 1 + 0.2 * np.sin(2 * np.pi * day / 365)

                # Add weekly pattern (lower on weekends)
                weekly_factor = 0.7 if current_date.weekday() >= 5 else 1.0

                # Add growth trend
                growth_factor = 1 + (day / 365) * 0.1

                licenses_used = int(
                    base_usage * seasonal_factor * weekly_factor * growth_factor +
                    np.random.normal(0, 5)
                )

                users_count = licenses_used + np.random.randint(5, 20)

                data.append({
                    'date': current_date,
                    'product': product,
                    'department': department,
                    'users_count': users_count,
                    'licenses_used': max(0, licenses_used)
                })

    return pd.DataFrame(data)


# Example usage
if __name__ == "__main__":
    # Generate sample data
    print("Generating sample data...")
    historical_data = generate_sample_data(days=365)

    # Initialize predictor
    predictor = LicensePredictor(model_type='random_forest')

    # Train model
    print("\nTraining model...")
    metrics = predictor.train(historical_data)

    print("\nModel Metrics:")
    print(f"  Test MAE: {metrics['test_mae']:.2f}")
    print(f"  Test RMSE: {metrics['test_rmse']:.2f}")
    print(f"  Test R²: {metrics['test_r2']:.3f}")

    # Make future predictions
    print("\nMaking 30-day predictions...")
    predictions = predictor.predict_future(
        historical_data,
        days_ahead=30,
        product='Creative Cloud'
    )

    print("\nPredictions for Creative Cloud (next 7 days):")
    print(predictions.head(7).to_string(index=False))

    # Get optimization recommendations
    recommendations = predictor.optimize_licenses(predictions)

    print("\nLicense Optimization Recommendations:")
    for product, rec in recommendations.items():
        print(f"\n{product}:")
        print(f"  Recommended allocation: {rec['recommended_allocation']} licenses")
        print(f"  Max predicted usage: {rec['max_predicted_usage']} licenses")
        print(f"  Average predicted usage: {rec['avg_predicted_usage']} licenses")

    # Save model
    predictor.save_model('models/license_predictor.pkl')
    print("\nModel saved to models/license_predictor.pkl")