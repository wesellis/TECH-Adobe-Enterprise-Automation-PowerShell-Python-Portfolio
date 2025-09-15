#!/usr/bin/env python3
"""
INTERMEDIATE LEVEL: License optimization with data analysis
Learning: Classes, data processing, pandas basics, reporting
"""

import json
import csv
from datetime import datetime, timedelta
from typing import List, Dict, Tuple
import random

class LicenseOptimizer:
    """Intermediate class-based approach"""

    def __init__(self, config_file: str = None):
        """Initialize with configuration"""
        self.config = self.load_config(config_file)
        self.users = []
        self.recommendations = []
        self.savings_potential = 0

    def load_config(self, config_file: str) -> Dict:
        """Load configuration with error handling"""
        try:
            if config_file:
                with open(config_file, 'r') as f:
                    return json.load(f)
        except FileNotFoundError:
            print(f"Warning: Config file {config_file} not found. Using defaults.")
        except json.JSONDecodeError:
            print(f"Warning: Invalid JSON in {config_file}. Using defaults.")

        # Default configuration
        return {
            'inactive_days_threshold': 30,
            'license_cost_monthly': 50,
            'optimization_aggressive': False
        }

    def load_user_data(self, data_source: str = 'mock') -> None:
        """Load user data from various sources"""
        if data_source == 'mock':
            self.users = self._generate_mock_data()
        elif data_source.endswith('.csv'):
            self.users = self._load_from_csv(data_source)
        elif data_source.endswith('.json'):
            self.users = self._load_from_json(data_source)
        else:
            raise ValueError(f"Unsupported data source: {data_source}")

        print(f"Loaded {len(self.users)} users for analysis")

    def _generate_mock_data(self) -> List[Dict]:
        """Generate realistic mock user data"""
        departments = ['Marketing', 'Design', 'Engineering', 'Sales', 'HR']
        products = ['Creative Cloud', 'Photoshop', 'Illustrator', 'Premiere', 'After Effects']

        users = []
        for i in range(100):
            # Create realistic usage patterns
            is_active = random.random() > 0.3  # 70% active users
            last_active_days = random.randint(0, 10) if is_active else random.randint(31, 180)

            users.append({
                'email': f'user{i}@company.com',
                'name': f'User {i}',
                'department': random.choice(departments),
                'products': random.sample(products, random.randint(1, 3)),
                'last_active_days': last_active_days,
                'usage_hours_monthly': random.randint(0, 200) if is_active else 0,
                'created_date': (datetime.now() - timedelta(days=random.randint(30, 730))).isoformat()
            })

        return users

    def _load_from_csv(self, filepath: str) -> List[Dict]:
        """Load user data from CSV file"""
        users = []
        try:
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    users.append(row)
        except Exception as e:
            print(f"Error loading CSV: {e}")
        return users

    def _load_from_json(self, filepath: str) -> List[Dict]:
        """Load user data from JSON file"""
        try:
            with open(filepath, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading JSON: {e}")
            return []

    def analyze_usage(self) -> Dict:
        """Analyze license usage patterns"""
        total_users = len(self.users)
        inactive_threshold = self.config['inactive_days_threshold']

        # Categorize users
        inactive_users = [u for u in self.users if u['last_active_days'] > inactive_threshold]
        rarely_used = [u for u in self.users if 0 < u.get('usage_hours_monthly', 0) < 10]
        heavy_users = [u for u in self.users if u.get('usage_hours_monthly', 0) > 100]

        # Department analysis
        dept_usage = {}
        for user in self.users:
            dept = user.get('department', 'Unknown')
            if dept not in dept_usage:
                dept_usage[dept] = {'total': 0, 'inactive': 0}
            dept_usage[dept]['total'] += 1
            if user['last_active_days'] > inactive_threshold:
                dept_usage[dept]['inactive'] += 1

        analysis = {
            'total_users': total_users,
            'inactive_users': len(inactive_users),
            'rarely_used': len(rarely_used),
            'heavy_users': len(heavy_users),
            'inactive_percentage': (len(inactive_users) / total_users * 100) if total_users > 0 else 0,
            'department_breakdown': dept_usage
        }

        return analysis

    def generate_recommendations(self) -> List[Dict]:
        """Generate actionable recommendations"""
        self.recommendations = []
        inactive_threshold = self.config['inactive_days_threshold']
        monthly_cost = self.config['license_cost_monthly']

        # Find users to reclaim licenses from
        for user in self.users:
            if user['last_active_days'] > inactive_threshold:
                priority = 'HIGH' if user['last_active_days'] > 90 else 'MEDIUM'
                self.recommendations.append({
                    'action': 'RECLAIM',
                    'user': user['email'],
                    'reason': f"Inactive for {user['last_active_days']} days",
                    'priority': priority,
                    'monthly_savings': monthly_cost,
                    'products': user.get('products', [])
                })

            elif user.get('usage_hours_monthly', 0) < 5:
                self.recommendations.append({
                    'action': 'DOWNGRADE',
                    'user': user['email'],
                    'reason': f"Low usage: {user.get('usage_hours_monthly', 0)} hours/month",
                    'priority': 'LOW',
                    'monthly_savings': monthly_cost * 0.5,
                    'products': user.get('products', [])
                })

        # Calculate total savings
        self.savings_potential = sum(rec['monthly_savings'] for rec in self.recommendations)

        return self.recommendations

    def export_report(self, format: str = 'console') -> None:
        """Export optimization report"""
        analysis = self.analyze_usage()
        recommendations = self.generate_recommendations()

        if format == 'console':
            self._print_console_report(analysis, recommendations)
        elif format == 'html':
            self._export_html_report(analysis, recommendations)
        elif format == 'csv':
            self._export_csv_report(recommendations)

    def _print_console_report(self, analysis: Dict, recommendations: List[Dict]) -> None:
        """Print formatted console report"""
        print("\n" + "=" * 60)
        print("          ADOBE LICENSE OPTIMIZATION REPORT")
        print("=" * 60)

        print(f"\n📊 USAGE ANALYSIS")
        print(f"   Total Users: {analysis['total_users']}")
        print(f"   Inactive Users: {analysis['inactive_users']} ({analysis['inactive_percentage']:.1f}%)")
        print(f"   Rarely Used: {analysis['rarely_used']}")
        print(f"   Heavy Users: {analysis['heavy_users']}")

        print(f"\n🏢 DEPARTMENT BREAKDOWN")
        for dept, stats in analysis['department_breakdown'].items():
            inactive_pct = (stats['inactive'] / stats['total'] * 100) if stats['total'] > 0 else 0
            print(f"   {dept}: {stats['total']} users ({stats['inactive']} inactive - {inactive_pct:.1f}%)")

        print(f"\n💰 OPTIMIZATION RECOMMENDATIONS")
        print(f"   Total Recommendations: {len(recommendations)}")
        print(f"   Potential Monthly Savings: ${self.savings_potential:,.2f}")
        print(f"   Potential Annual Savings: ${self.savings_potential * 12:,.2f}")

        # Show top recommendations
        high_priority = [r for r in recommendations if r['priority'] == 'HIGH']
        if high_priority:
            print(f"\n🔴 HIGH PRIORITY ACTIONS ({len(high_priority)} items):")
            for rec in high_priority[:5]:
                print(f"   • {rec['action']}: {rec['user']}")
                print(f"     Reason: {rec['reason']}")
                print(f"     Savings: ${rec['monthly_savings']}/month")

    def _export_html_report(self, analysis: Dict, recommendations: List[Dict]) -> None:
        """Export HTML report"""
        html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>License Optimization Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                   color: white; padding: 30px; border-radius: 10px; }}
        .metric-card {{ background: white; padding: 20px; margin: 10px;
                       border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        .savings {{ color: #4caf50; font-size: 32px; font-weight: bold; }}
        .high {{ background: #ffebee; border-left: 4px solid #f44336; }}
        .medium {{ background: #fff3e0; border-left: 4px solid #ff9800; }}
        .low {{ background: #e3f2fd; border-left: 4px solid #2196f3; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
        th {{ background: #f0f0f0; padding: 12px; text-align: left; }}
        td {{ padding: 10px; border-bottom: 1px solid #ddd; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Adobe License Optimization Report</h1>
            <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>

        <div class="metric-card">
            <h2>💰 Savings Potential</h2>
            <div class="savings">${self.savings_potential:,.2f}/month</div>
            <p>Annual Savings: ${self.savings_potential * 12:,.2f}</p>
        </div>

        <div class="metric-card">
            <h2>📊 Usage Metrics</h2>
            <p>Total Users: {analysis['total_users']}</p>
            <p>Inactive Users: {analysis['inactive_users']} ({analysis['inactive_percentage']:.1f}%)</p>
            <p>Optimization Opportunities: {len(recommendations)}</p>
        </div>

        <div class="metric-card">
            <h2>Recommendations</h2>
            <table>
                <tr>
                    <th>Priority</th>
                    <th>Action</th>
                    <th>User</th>
                    <th>Reason</th>
                    <th>Monthly Savings</th>
                </tr>
"""

        for rec in sorted(recommendations, key=lambda x: x['priority']):
            priority_class = rec['priority'].lower()
            html += f"""
                <tr class="{priority_class}">
                    <td>{rec['priority']}</td>
                    <td>{rec['action']}</td>
                    <td>{rec['user']}</td>
                    <td>{rec['reason']}</td>
                    <td>${rec['monthly_savings']:.2f}</td>
                </tr>
"""

        html += """
            </table>
        </div>
    </div>
</body>
</html>
"""

        filename = f"license_optimization_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
        with open(filename, 'w') as f:
            f.write(html)
        print(f"\n📄 HTML report saved: {filename}")

    def _export_csv_report(self, recommendations: List[Dict]) -> None:
        """Export recommendations to CSV"""
        filename = f"recommendations_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

        with open(filename, 'w', newline='') as f:
            fieldnames = ['priority', 'action', 'user', 'reason', 'monthly_savings', 'products']
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()

            for rec in recommendations:
                rec['products'] = ', '.join(rec.get('products', []))
                writer.writerow(rec)

        print(f"\n📄 CSV report saved: {filename}")


def main():
    """Main execution with command-line interface"""
    print("🚀 Adobe License Optimizer - Intermediate Level")
    print("-" * 50)

    # Create optimizer instance
    optimizer = LicenseOptimizer()

    # Load and analyze data
    print("Loading user data...")
    optimizer.load_user_data('mock')  # Use mock data for demo

    # Generate analysis
    analysis = optimizer.analyze_usage()

    # Generate recommendations
    recommendations = optimizer.generate_recommendations()

    # Export reports
    optimizer.export_report('console')
    optimizer.export_report('html')

    print("\n✅ Optimization complete!")
    print(f"💡 Implement these recommendations to save ${optimizer.savings_potential * 12:,.2f} annually")


if __name__ == "__main__":
    main()