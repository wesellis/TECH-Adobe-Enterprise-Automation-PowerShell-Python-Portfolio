import React from 'react';
import {
  Box,
  Grid,
  Paper,
  Typography,
  Card,
  CardContent,
  LinearProgress,
} from '@mui/material';
import {
  People as PeopleIcon,
  Assignment as LicenseIcon,
  TrendingUp as TrendingIcon,
  AttachMoney as MoneyIcon,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { useQuery } from 'react-query';
import { format } from 'date-fns';
import api from '../services/api';

// Stat Card Component
const StatCard = ({ title, value, icon, color, change }) => (
  <Card elevation={2}>
    <CardContent>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 48,
            height: 48,
            borderRadius: 2,
            bgcolor: `${color}.light`,
            color: `${color}.main`,
            mr: 2,
          }}
        >
          {icon}
        </Box>
        <Box sx={{ flexGrow: 1 }}>
          <Typography color="textSecondary" gutterBottom variant="body2">
            {title}
          </Typography>
          <Typography variant="h4" component="h2">
            {value}
          </Typography>
          {change && (
            <Typography
              variant="body2"
              sx={{
                color: change > 0 ? 'success.main' : 'error.main',
                mt: 0.5,
              }}
            >
              {change > 0 ? '+' : ''}{change}% from last month
            </Typography>
          )}
        </Box>
      </Box>
    </CardContent>
  </Card>
);

const Dashboard = () => {
  // Fetch dashboard data
  const { data: stats, isLoading: statsLoading } = useQuery(
    'dashboardStats',
    () => api.getDashboardStats(),
    { refetchInterval: 60000 } // Refresh every minute
  );

  const { data: licenseData } = useQuery('licenseUtilization', () =>
    api.getLicenseUtilization()
  );

  const { data: usageHistory } = useQuery('usageHistory', () =>
    api.getUsageHistory()
  );

  // Sample data for charts (replace with real API data)
  const monthlyUsage = [
    { month: 'Jan', users: 450, licenses: 480 },
    { month: 'Feb', users: 465, licenses: 490 },
    { month: 'Mar', users: 478, licenses: 495 },
    { month: 'Apr', users: 490, licenses: 500 },
    { month: 'May', users: 495, licenses: 505 },
    { month: 'Jun', users: 502, licenses: 510 },
  ];

  const productDistribution = [
    { name: 'Creative Cloud', value: 350, color: '#DA1F26' },
    { name: 'Photoshop', value: 120, color: '#FF6B6B' },
    { name: 'Illustrator', value: 80, color: '#4ECDC4' },
    { name: 'Premiere Pro', value: 60, color: '#45B7D1' },
    { name: 'Others', value: 40, color: '#96CEB4' },
  ];

  const departmentUsage = [
    { dept: 'Marketing', allocated: 150, used: 142 },
    { dept: 'Design', allocated: 200, used: 185 },
    { dept: 'Engineering', allocated: 100, used: 78 },
    { dept: 'Sales', allocated: 80, used: 65 },
    { dept: 'HR', allocated: 50, used: 38 },
  ];

  if (statsLoading) {
    return <LinearProgress />;
  }

  return (
    <Box>
      <Typography variant="h4" gutterBottom sx={{ mb: 3 }}>
        Dashboard
      </Typography>

      {/* Stats Cards */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Total Users"
            value={stats?.totalUsers || '512'}
            icon={<PeopleIcon />}
            color="primary"
            change={5.2}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Active Licenses"
            value={stats?.activeLicenses || '487'}
            icon={<LicenseIcon />}
            color="secondary"
            change={-2.1}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Utilization Rate"
            value={stats?.utilizationRate || '78%'}
            icon={<TrendingIcon />}
            color="success"
            change={8.3}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Monthly Cost"
            value={stats?.monthlyCost || '$38,924'}
            icon={<MoneyIcon />}
            color="warning"
            change={-3.5}
          />
        </Grid>
      </Grid>

      {/* Charts */}
      <Grid container spacing={3}>
        {/* Usage Trend */}
        <Grid item xs={12} md={8}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              Usage Trend
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={monthlyUsage}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Line
                  type="monotone"
                  dataKey="users"
                  stroke="#DA1F26"
                  name="Active Users"
                  strokeWidth={2}
                />
                <Line
                  type="monotone"
                  dataKey="licenses"
                  stroke="#2196f3"
                  name="Total Licenses"
                  strokeWidth={2}
                />
              </LineChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>

        {/* Product Distribution */}
        <Grid item xs={12} md={4}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              Product Distribution
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={productDistribution}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, percent }) =>
                    `${name} ${(percent * 100).toFixed(0)}%`
                  }
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {productDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>

        {/* Department Usage */}
        <Grid item xs={12}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              Department License Usage
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={departmentUsage}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="dept" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Bar dataKey="allocated" fill="#e3f2fd" name="Allocated" />
                <Bar dataKey="used" fill="#2196f3" name="Used" />
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>
      </Grid>

      {/* Recent Activity */}
      <Grid container spacing={3} sx={{ mt: 2 }}>
        <Grid item xs={12}>
          <Paper sx={{ p: 3 }}>
            <Typography variant="h6" gutterBottom>
              Recent Activity
            </Typography>
            <Box sx={{ mt: 2 }}>
              {[1, 2, 3, 4, 5].map((item) => (
                <Box
                  key={item}
                  sx={{
                    display: 'flex',
                    alignItems: 'center',
                    py: 1.5,
                    borderBottom: '1px solid',
                    borderColor: 'divider',
                    '&:last-child': { borderBottom: 0 },
                  }}
                >
                  <Box sx={{ flexGrow: 1 }}>
                    <Typography variant="body1">
                      New user provisioned: john.doe@company.com
                    </Typography>
                    <Typography variant="caption" color="textSecondary">
                      {format(new Date(), 'MMM dd, yyyy HH:mm')}
                    </Typography>
                  </Box>
                  <Typography variant="body2" color="success.main">
                    Completed
                  </Typography>
                </Box>
              ))}
            </Box>
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;