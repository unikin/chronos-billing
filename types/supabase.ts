export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          id: string
          name: string
          parent_account_id: string | null
          status: string
          timezone: string
        }
        Insert: {
          id?: string
          name: string
          parent_account_id?: string | null
          status: string
          timezone?: string
        }
        Update: {
          id?: string
          name?: string
          parent_account_id?: string | null
          status?: string
          timezone?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_parent_account_id_fkey"
            columns: ["parent_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      billable_metrics: {
        Row: {
          aggregation_type: string
          event_name: string
          group_keys: string[] | null
          id: string
          name: string
          property_key: string | null
          sql_definition: string | null
        }
        Insert: {
          aggregation_type: string
          event_name: string
          group_keys?: string[] | null
          id?: string
          name: string
          property_key?: string | null
          sql_definition?: string | null
        }
        Update: {
          aggregation_type?: string
          event_name?: string
          group_keys?: string[] | null
          id?: string
          name?: string
          property_key?: string | null
          sql_definition?: string | null
        }
        Relationships: []
      }
      credit_ledgers: {
        Row: {
          account_id: string
          amount: number
          created_at: string
          currency: string
          id: string
          reference_id: string | null
          reference_type: string
          running_balance: number
          transaction_type: string
        }
        Insert: {
          account_id: string
          amount?: number
          created_at?: string
          currency?: string
          id?: string
          reference_id?: string | null
          reference_type: string
          running_balance?: number
          transaction_type: string
        }
        Update: {
          account_id?: string
          amount?: number
          created_at?: string
          currency?: string
          id?: string
          reference_id?: string | null
          reference_type?: string
          running_balance?: number
          transaction_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "credit_ledgers_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_line_items: {
        Row: {
          amount: number
          id: string
          invoice_id: string
          metric_id: string
          quantity: number
        }
        Insert: {
          amount?: number
          id?: string
          invoice_id: string
          metric_id: string
          quantity?: number
        }
        Update: {
          amount?: number
          id?: string
          invoice_id?: string
          metric_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_line_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_line_items_metric_id_fkey"
            columns: ["metric_id"]
            isOneToOne: false
            referencedRelation: "billable_metrics"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          account_id: string
          billing_period_end: string | null
          billing_period_start: string | null
          id: string
          status: string
          subtotal: number
          total_amount: number
        }
        Insert: {
          account_id: string
          billing_period_end?: string | null
          billing_period_start?: string | null
          id?: string
          status: string
          subtotal?: number
          total_amount?: number
        }
        Update: {
          account_id?: string
          billing_period_end?: string | null
          billing_period_start?: string | null
          id?: string
          status?: string
          subtotal?: number
          total_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoices_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      price_dimensions: {
        Row: {
          dimension_key: string
          dimension_value: string
          id: string
          price_id: string
        }
        Insert: {
          dimension_key: string
          dimension_value: string
          id?: string
          price_id: string
        }
        Update: {
          dimension_key?: string
          dimension_value?: string
          id?: string
          price_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "price_dimensions_price_id_fkey"
            columns: ["price_id"]
            isOneToOne: false
            referencedRelation: "prices"
            referencedColumns: ["id"]
          },
        ]
      }
      price_tiers: {
        Row: {
          first_unit: number
          flat_amount: number
          id: string
          last_unit: number | null
          price_id: string
          unit_amount: number
        }
        Insert: {
          first_unit?: number
          flat_amount?: number
          id?: string
          last_unit?: number | null
          price_id: string
          unit_amount?: number
        }
        Update: {
          first_unit?: number
          flat_amount?: number
          id?: string
          last_unit?: number | null
          price_id?: string
          unit_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "price_tiers_price_id_fkey"
            columns: ["price_id"]
            isOneToOne: false
            referencedRelation: "prices"
            referencedColumns: ["id"]
          },
        ]
      }
      prices: {
        Row: {
          effective_end: string | null
          effective_start: string
          id: string
          metric_id: string
          pricing_model: string
          rate_card_id: string
        }
        Insert: {
          effective_end?: string | null
          effective_start: string
          id?: string
          metric_id: string
          pricing_model: string
          rate_card_id: string
        }
        Update: {
          effective_end?: string | null
          effective_start?: string
          id?: string
          metric_id?: string
          pricing_model?: string
          rate_card_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prices_metric_id_fkey"
            columns: ["metric_id"]
            isOneToOne: false
            referencedRelation: "billable_metrics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prices_rate_card_id_fkey"
            columns: ["rate_card_id"]
            isOneToOne: false
            referencedRelation: "rate_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          id: string
          name: string
        }
        Insert: {
          id?: string
          name: string
        }
        Update: {
          id?: string
          name?: string
        }
        Relationships: []
      }
      rate_cards: {
        Row: {
          id: string
          product_id: string
        }
        Insert: {
          id?: string
          product_id: string
        }
        Update: {
          id?: string
          product_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rate_cards_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          account_id: string
          billing_interval: string
          current_period_end: string
          current_period_start: string
          id: string
          rate_card_id: string
          status: string
        }
        Insert: {
          account_id: string
          billing_interval: string
          current_period_end: string
          current_period_start: string
          id?: string
          rate_card_id: string
          status: string
        }
        Update: {
          account_id?: string
          billing_interval?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          rate_card_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_rate_card_id_fkey"
            columns: ["rate_card_id"]
            isOneToOne: false
            referencedRelation: "rate_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_events: {
        Row: {
          account_id: string
          event_name: string
          id: string
          idempotency_key: string
          ingested_at: string | null
          properties: Json | null
          timestamp: string
        }
        Insert: {
          account_id: string
          event_name: string
          id?: string
          idempotency_key: string
          ingested_at?: string | null
          properties?: Json | null
          timestamp: string
        }
        Update: {
          account_id?: string
          event_name?: string
          id?: string
          idempotency_key?: string
          ingested_at?: string | null
          properties?: Json | null
          timestamp?: string
        }
        Relationships: [
          {
            foreignKeyName: "usage_events_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_events_archive: {
        Row: {
          account_id: string | null
          event_name: string | null
          id: string
          idempotency_key: string | null
          ingested_at: string | null
          properties: Json | null
          timestamp: string | null
        }
        Insert: {
          account_id?: string | null
          event_name?: string | null
          id: string
          idempotency_key?: string | null
          ingested_at?: string | null
          properties?: Json | null
          timestamp?: string | null
        }
        Update: {
          account_id?: string | null
          event_name?: string | null
          id?: string
          idempotency_key?: string | null
          ingested_at?: string | null
          properties?: Json | null
          timestamp?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      v_dashboard_events: {
        Row: {
          account_id: string | null
          endpoint: string | null
          id: string | null
          is_flagged_anomaly: boolean | null
          timestamp: string | null
          tokens_used: number | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      v_usage_anomalies: {
        Row: {
          account_id: string | null
          endpoint: string | null
          event_name: string | null
          id: string | null
          ingested_at: string | null
          is_flagged_anomaly: boolean | null
          over_threshold_by: number | null
          region: string | null
          status_code: number | null
          timestamp: string | null
          tokens_used: number | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
    }
    Functions: {
      generate_monthly_invoice: {
        Args: {
          p_account_id: string
          p_target_month: string
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
